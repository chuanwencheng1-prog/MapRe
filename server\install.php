<?php
/**
 * 卡密授权系统 - 自助安装向导
 * 访问 http://your.domain.com/pc_auth/install.php 按步骤完成安装
 */

session_start();
define('PC_ROOT', __DIR__);
$CFG_FILE   = PC_ROOT . '/includes/config.php';
$INSTALL_LOCK = PC_ROOT . '/data/install.lock';
$RSA_DIR    = PC_ROOT . '/keys';
$DATA_DIR   = PC_ROOT . '/data';

// 已安装保护
if (file_exists($INSTALL_LOCK) && empty($_GET['force'])) {
    die('<meta charset="utf-8">系统已安装。如需重装请手动删除 <code>data/install.lock</code> 文件。');
}

// 自动确保目录存在
@mkdir($DATA_DIR, 0755, true);
@mkdir($RSA_DIR,  0700, true);
@mkdir(PC_ROOT . '/includes', 0755, true);

$step = isset($_GET['step']) ? (int)$_GET['step'] : 1;
$err = '';
$ok  = '';

/* ---------------------- 步骤处理 ---------------------- */

if ($step === 2 && $_SERVER['REQUEST_METHOD'] === 'POST') {
    // 保存数据库配置 + 建表
    $db = [
        'host' => trim($_POST['db_host'] ?? '127.0.0.1'),
        'port' => (int)($_POST['db_port'] ?? 3306),
        'name' => trim($_POST['db_name'] ?? ''),
        'user' => trim($_POST['db_user'] ?? ''),
        'pass' => (string)($_POST['db_pass'] ?? ''),
        'pref' => trim($_POST['db_pref'] ?? 'pc_'),
    ];
    if (!$db['name'] || !$db['user']) {
        $err = '数据库名称和用户名必填';
    } else {
        try {
            $dsn = "mysql:host={$db['host']};port={$db['port']};charset=utf8mb4";
            $pdo = new PDO($dsn, $db['user'], $db['pass'], [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            ]);
            // 若库不存在则创建
            $pdo->exec("CREATE DATABASE IF NOT EXISTS `{$db['name']}` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci");
            $pdo->exec("USE `{$db['name']}`");
            $p = $db['pref'];

            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$p}admin` (
                id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(64) NOT NULL UNIQUE,
                password VARCHAR(255) NOT NULL,
                created_at INT UNSIGNED NOT NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$p}cards` (
                id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                card_key VARCHAR(64) NOT NULL UNIQUE,
                type VARCHAR(16) NOT NULL DEFAULT 'day',
                duration INT UNSIGNED NOT NULL DEFAULT 86400,
                status TINYINT NOT NULL DEFAULT 0,
                device_id VARCHAR(128) DEFAULT NULL,
                bound_at INT UNSIGNED DEFAULT NULL,
                expires_at INT UNSIGNED DEFAULT NULL,
                batch VARCHAR(32) DEFAULT NULL,
                note VARCHAR(255) DEFAULT NULL,
                created_at INT UNSIGNED NOT NULL,
                INDEX idx_status (status),
                INDEX idx_device (device_id),
                INDEX idx_batch  (batch)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$p}devices` (
                id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                device_id VARCHAR(128) NOT NULL UNIQUE,
                card_id INT UNSIGNED DEFAULT NULL,
                model VARCHAR(64) DEFAULT NULL,
                sys   VARCHAR(32) DEFAULT NULL,
                name  VARCHAR(128) DEFAULT NULL,
                bundle VARCHAR(128) DEFAULT NULL,
                ip VARCHAR(64) DEFAULT NULL,
                first_seen INT UNSIGNED NOT NULL,
                last_seen  INT UNSIGNED NOT NULL,
                status TINYINT NOT NULL DEFAULT 1
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$p}logs` (
                id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                type VARCHAR(32) NOT NULL,
                card VARCHAR(64) DEFAULT NULL,
                device_id VARCHAR(128) DEFAULT NULL,
                ip VARCHAR(64) DEFAULT NULL,
                content TEXT,
                created_at INT UNSIGNED NOT NULL,
                INDEX idx_type (type),
                INDEX idx_time (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

            $pdo->exec("CREATE TABLE IF NOT EXISTS `{$p}config` (
                `key` VARCHAR(64) PRIMARY KEY,
                `value` TEXT
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

            $_SESSION['install_db'] = $db;
            header('Location: install.php?step=3'); exit;
        } catch (Exception $e) {
            $err = '数据库连接/建表失败：' . $e->getMessage();
        }
    }
}

if ($step === 3 && $_SERVER['REQUEST_METHOD'] === 'POST') {
    // 保存管理员账号 + APP_ID + 生成 RSA + 写 config.php
    $db = $_SESSION['install_db'] ?? null;
    if (!$db) { header('Location: install.php?step=2'); exit; }

    $admin_user = trim($_POST['admin_user'] ?? '');
    $admin_pass = (string)($_POST['admin_pass'] ?? '');
    $app_id     = trim($_POST['app_id'] ?? 'pcui_default');
    $site_name  = trim($_POST['site_name'] ?? '卡密授权系统');

    if (strlen($admin_user) < 3 || strlen($admin_pass) < 6) {
        $err = '账号至少 3 位、密码至少 6 位';
    } else {
        try {
            // 生成 RSA 2048 密钥对
            $res = openssl_pkey_new([
                'digest_alg' => 'sha256',
                'private_key_bits' => 2048,
                'private_key_type' => OPENSSL_KEYTYPE_RSA,
            ]);
            if (!$res) throw new Exception('OpenSSL 生成密钥失败，请确认 openssl 扩展');
            openssl_pkey_export($res, $privPem);
            $pubPem = openssl_pkey_get_details($res)['key'];

            file_put_contents($RSA_DIR . '/private.pem', $privPem);
            file_put_contents($RSA_DIR . '/public.pem',  $pubPem);
            @chmod($RSA_DIR . '/private.pem', 0600);

            // 写 config.php
            $sec = bin2hex(random_bytes(16));
            $cfg = "<?php\n// 由 install.php 自动生成\nreturn [\n"
                 . "  'db' => [\n"
                 . "    'host' => ".var_export($db['host'],true).",\n"
                 . "    'port' => ".(int)$db['port'].",\n"
                 . "    'name' => ".var_export($db['name'],true).",\n"
                 . "    'user' => ".var_export($db['user'],true).",\n"
                 . "    'pass' => ".var_export($db['pass'],true).",\n"
                 . "    'pref' => ".var_export($db['pref'],true).",\n"
                 . "  ],\n"
                 . "  'app_id'    => ".var_export($app_id,true).",\n"
                 . "  'site_name' => ".var_export($site_name,true).",\n"
                 . "  'session_secret' => ".var_export($sec,true).",\n"
                 . "  'rsa_private' => __DIR__ . '/../keys/private.pem',\n"
                 . "  'rsa_public'  => __DIR__ . '/../keys/public.pem',\n"
                 . "];\n";
            file_put_contents($CFG_FILE, $cfg);

            // 建管理员
            $dsn = "mysql:host={$db['host']};port={$db['port']};dbname={$db['name']};charset=utf8mb4";
            $pdo = new PDO($dsn, $db['user'], $db['pass'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
            $p = $db['pref'];
            $hash = password_hash($admin_pass, PASSWORD_DEFAULT);
            $stmt = $pdo->prepare("INSERT INTO `{$p}admin` (username, password, created_at) VALUES (?,?,?)
                                   ON DUPLICATE KEY UPDATE password=VALUES(password)");
            $stmt->execute([$admin_user, $hash, time()]);

            // 写 install.lock
            file_put_contents($INSTALL_LOCK, date('Y-m-d H:i:s'));

            unset($_SESSION['install_db']);
            $_SESSION['installed_pub'] = $pubPem;
            header('Location: install.php?step=4'); exit;
        } catch (Exception $e) {
            $err = '初始化失败：' . $e->getMessage();
        }
    }
}

/* ---------------------- 环境检测 ---------------------- */

function check_env() {
    $checks = [];
    $checks[] = ['PHP 版本 ≥ 7.2',     version_compare(PHP_VERSION,'7.2.0','>='), PHP_VERSION];
    $checks[] = ['PDO MySQL 扩展',     extension_loaded('pdo_mysql'), extension_loaded('pdo_mysql')?'已启用':'未启用'];
    $checks[] = ['OpenSSL 扩展',       extension_loaded('openssl'),   extension_loaded('openssl')?'已启用':'未启用'];
    $checks[] = ['JSON 扩展',          extension_loaded('json'),      extension_loaded('json')?'已启用':'未启用'];
    $checks[] = ['data/ 可写',        is_writable(__DIR__.'/data') || is_writable(__DIR__), is_writable(__DIR__.'/data')?'可写':'需授权 755'];
    $checks[] = ['includes/ 可写',    is_writable(__DIR__.'/includes') || is_writable(__DIR__), is_writable(__DIR__.'/includes')?'可写':'需授权 755'];
    $checks[] = ['keys/ 可写',        is_writable(__DIR__.'/keys') || is_writable(__DIR__), is_writable(__DIR__.'/keys')?'可写':'需授权 700'];
    return $checks;
}
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>卡密授权系统 - 安装向导</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;
    background:linear-gradient(135deg,#1677ff 0%,#0958d9 100%);min-height:100vh;padding:40px 16px;color:#333}
.wrap{max-width:720px;margin:0 auto;background:#fff;border-radius:20px;box-shadow:0 20px 60px rgba(0,0,0,0.15);overflow:hidden}
.hd{padding:28px 36px;background:linear-gradient(135deg,#1677ff,#0958d9);color:#fff}
.hd h1{font-size:22px;font-weight:600}
.hd p{opacity:.9;margin-top:4px;font-size:13px}
.steps{display:flex;padding:16px 36px;border-bottom:1px solid #f0f2f5;background:#fafbfc}
.steps .s{flex:1;text-align:center;font-size:13px;color:#999}
.steps .s.active{color:#1677ff;font-weight:600}
.steps .s .n{display:inline-block;width:22px;height:22px;line-height:22px;border-radius:50%;background:#eee;color:#999;margin-right:6px;font-size:12px}
.steps .s.active .n{background:#1677ff;color:#fff}
.body{padding:32px 36px}
.body h2{font-size:18px;margin-bottom:16px}
.check{margin:16px 0}
.check .row{display:flex;justify-content:space-between;padding:10px 14px;border-bottom:1px solid #f0f2f5;font-size:14px}
.check .row:last-child{border-bottom:0}
.tag-ok{color:#00b96b;font-weight:600}
.tag-no{color:#e74c3c;font-weight:600}
.field{margin:14px 0}
.field label{display:block;font-size:13px;color:#666;margin-bottom:6px}
.field input{width:100%;padding:10px 12px;border:1px solid #e4e7eb;border-radius:8px;font-size:14px;background:#fafbfc}
.field input:focus{outline:none;border-color:#1677ff;background:#fff}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.btn{display:inline-block;padding:12px 28px;background:linear-gradient(135deg,#1677ff,#0958d9);color:#fff;border:0;border-radius:10px;font-size:15px;font-weight:600;cursor:pointer;text-decoration:none}
.btn:hover{opacity:.9}
.btn-gray{background:#f0f2f5;color:#555}
.err{padding:12px 14px;background:#fef0f0;border:1px solid #fde2e2;border-radius:8px;color:#e74c3c;font-size:13px;margin-bottom:16px}
.ok{padding:12px 14px;background:#f0f9eb;border:1px solid #e1f3d8;border-radius:8px;color:#67c23a;font-size:13px;margin-bottom:16px}
.pem{background:#1e1e1e;color:#d4d4d4;font-family:Menlo,Consolas,monospace;font-size:12px;padding:14px;border-radius:8px;max-height:300px;overflow:auto;white-space:pre}
.actions{margin-top:24px;display:flex;justify-content:space-between}
small{color:#999}
</style>
</head>
<body>
<div class="wrap">
  <div class="hd">
    <h1>🔐 卡密授权系统</h1>
    <p>4 步自助安装 · 支持 RSA 签名防破解 · 一机一码</p>
  </div>
  <div class="steps">
    <div class="s <?= $step>=1?'active':'' ?>"><span class="n">1</span>环境检测</div>
    <div class="s <?= $step>=2?'active':'' ?>"><span class="n">2</span>数据库</div>
    <div class="s <?= $step>=3?'active':'' ?>"><span class="n">3</span>管理员</div>
    <div class="s <?= $step>=4?'active':'' ?>"><span class="n">4</span>完成</div>
  </div>
  <div class="body">
    <?php if ($err): ?><div class="err"><?= htmlspecialchars($err) ?></div><?php endif; ?>
    <?php if ($ok):  ?><div class="ok"><?= htmlspecialchars($ok)  ?></div><?php endif; ?>

    <?php if ($step === 1): ?>
      <h2>① 环境检测</h2>
      <?php $checks = check_env(); $allOk = true; ?>
      <div class="check">
        <?php foreach ($checks as $c): if (!$c[1]) $allOk = false; ?>
          <div class="row">
            <span><?= $c[0] ?></span>
            <span class="<?= $c[1]?'tag-ok':'tag-no' ?>"><?= $c[1]?'✓ ':'✗ ' ?><?= htmlspecialchars($c[2]) ?></span>
          </div>
        <?php endforeach; ?>
      </div>
      <?php if (!$allOk): ?>
        <div class="err">请先解决上述环境问题再继续。</div>
      <?php endif; ?>
      <div class="actions">
        <span></span>
        <a class="btn <?= $allOk?'':'btn-gray' ?>" href="<?= $allOk?'install.php?step=2':'#' ?>">下一步 →</a>
      </div>

    <?php elseif ($step === 2): ?>
      <h2>② 数据库配置</h2>
      <form method="post">
        <div class="grid2">
          <div class="field"><label>数据库主机</label><input name="db_host" value="127.0.0.1" required></div>
          <div class="field"><label>端口</label><input name="db_port" value="3306" required></div>
        </div>
        <div class="field"><label>数据库名称（不存在会自动创建）</label><input name="db_name" placeholder="pc_auth" required></div>
        <div class="grid2">
          <div class="field"><label>用户名</label><input name="db_user" required></div>
          <div class="field"><label>密码</label><input name="db_pass" type="password"></div>
        </div>
        <div class="field"><label>表前缀</label><input name="db_pref" value="pc_" required></div>
        <div class="actions">
          <a class="btn btn-gray" href="install.php?step=1">← 上一步</a>
          <button class="btn" type="submit">测试连接并建表 →</button>
        </div>
      </form>

    <?php elseif ($step === 3): ?>
      <h2>③ 管理员账号 & APP_ID</h2>
      <form method="post">
        <div class="field"><label>站点名称</label><input name="site_name" value="卡密授权系统"></div>
        <div class="field">
            <label>APP_ID <small>（必须与 iOS 端 PCAuthManager.m 的 kPCAuthAppID 一致）</small></label>
            <input name="app_id" value="pcui_default" required>
        </div>
        <div class="grid2">
          <div class="field"><label>管理员账号</label><input name="admin_user" required minlength="3"></div>
          <div class="field"><label>管理员密码</label><input name="admin_pass" type="password" required minlength="6"></div>
        </div>
        <div class="actions">
          <a class="btn btn-gray" href="install.php?step=2">← 上一步</a>
          <button class="btn" type="submit">生成 RSA 密钥并完成安装 →</button>
        </div>
      </form>

    <?php elseif ($step === 4): ?>
      <h2>🎉 安装完成</h2>
      <p style="color:#666;margin-bottom:16px">请把下方 <b>公钥</b> 全文复制，覆盖 iOS 端 <code>PCAuthManager.m</code> 里的 <code>kPCAuthPubKeyPEM</code>：</p>
      <div class="pem"><?= htmlspecialchars($_SESSION['installed_pub'] ?? file_get_contents($RSA_DIR.'/public.pem')) ?></div>
      <div class="ok" style="margin-top:16px">
        ✅ 同时请把 iOS 端 <code>kPCAuthServerBase</code> 改为本站目录，例如：<b><?= htmlspecialchars((isset($_SERVER['HTTPS'])&&$_SERVER['HTTPS']!=='off'?'https://':'http://').$_SERVER['HTTP_HOST'].rtrim(dirname($_SERVER['PHP_SELF']),'/\\')) ?></b>
      </div>
      <div class="actions">
        <a class="btn btn-gray" href="admin/login.php">前往后台登录</a>
        <a class="btn" href="admin/login.php">登录管理后台 →</a>
      </div>
      <p style="margin-top:20px;font-size:12px;color:#999">安全提醒：请手动删除或重命名本文件 <code>install.php</code>，防止二次安装。</p>
    <?php endif; ?>
  </div>
</div>
</body>
</html>
