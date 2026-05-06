<?php
/**
 * PersonalCenterUI 网络验证 —— 自助安装向导
 *   步骤：1 环境检测 → 2 数据库配置 → 3 管理员账号 → 4 生成密钥并完成
 *   完成后写入 config.php + install.lock，后续访问直接 302 到 admin.php。
 *
 *   防重装：install.lock 存在即拒绝再次进入本向导。
 *   手机适配：单栏自适应、meta viewport、触控尺寸 >= 44pt。
 */
declare(strict_types=1);
define('PC_AUTH_ENTRY', 1);
require __DIR__ . '/includes/helper.php';

if (session_status() === PHP_SESSION_NONE) {
    session_name('PC_INSTALL');
    session_start();
}

$ROOT = __DIR__;
$LOCK = $ROOT . '/install.lock';
$CFG  = $ROOT . '/config.php';

if (is_file($LOCK)) {
    header('Location: admin.php'); exit;
}

$step = (int)($_GET['step'] ?? $_POST['step'] ?? 1);
$err  = '';
$ok   = '';

function render(string $title, string $body, int $step, string $err = '', string $ok = ''): void {
    $CSS = 'assets/style.css';
    ?><!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title><?= h($title) ?> - PersonalCenterUI 验证</title>
<link rel="stylesheet" href="<?= h($CSS) ?>">
</head><body class="pc-install">
<div class="pc-wrap">
  <header class="pc-header">
    <div class="pc-logo">PersonalCenterUI · 网络验证</div>
    <div class="pc-sub">自助安装向导</div>
  </header>
  <ol class="pc-steps">
    <li class="<?= $step>=1?'on':'' ?>">① 环境检测</li>
    <li class="<?= $step>=2?'on':'' ?>">② 数据库</li>
    <li class="<?= $step>=3?'on':'' ?>">③ 管理员</li>
    <li class="<?= $step>=4?'on':'' ?>">④ 完成</li>
  </ol>
  <?php if ($err): ?><div class="pc-alert err"><?= h($err) ?></div><?php endif; ?>
  <?php if ($ok):  ?><div class="pc-alert ok"><?= h($ok) ?></div><?php endif; ?>
  <section class="pc-card"><?= $body ?></section>
  <footer class="pc-footer">© PersonalCenterUI Auth · 安装完成后此页将自动关闭</footer>
</div>
</body></html><?php
}

/* -------------------- 步骤 1：环境检测 -------------------- */
if ($step === 1) {
    $checks = [
        ['PHP 版本 ≥ 7.4',        version_compare(PHP_VERSION, '7.4', '>=')],
        ['PDO 扩展',              extension_loaded('pdo')],
        ['OpenSSL 扩展',          extension_loaded('openssl')],
        ['JSON 扩展',             extension_loaded('json')],
        ['PDO SQLite 驱动',       extension_loaded('pdo_sqlite')],
        ['PDO MySQL 驱动（可选）', extension_loaded('pdo_mysql')],
        ['config.php 可写',      is_writable($ROOT)],
        ['data/ 可创建',          @mkdir($ROOT.'/data', 0700, true) || is_dir($ROOT.'/data')],
    ];
    $pass = true;
    ob_start(); ?>
    <h2>环境检测</h2>
    <p class="pc-desc">检测服务器是否满足运行条件。可选项不影响安装。</p>
    <table class="pc-table">
    <?php foreach ($checks as $c):
        $must = strpos($c[0], '可选') === false;
        if ($must && !$c[1]) $pass = false; ?>
      <tr>
        <td><?= h($c[0]) ?></td>
        <td class="<?= $c[1]?'ok':($must?'err':'warn') ?>"><?= $c[1] ? 'OK' : ($must?'缺失':'未启用') ?></td>
      </tr>
    <?php endforeach; ?>
    </table>
    <form method="get" class="pc-form">
      <input type="hidden" name="step" value="2">
      <button class="pc-btn" <?= $pass?'':'disabled' ?>>下一步 →</button>
    </form>
    <?php
    render('环境检测', ob_get_clean(), 1);
    exit;
}

/* -------------------- 步骤 2：数据库配置 -------------------- */
if ($step === 2) {
    $driver = $_POST['driver'] ?? 'sqlite';
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && !empty($_POST['do'])) {
        try {
            if ($driver === 'mysql') {
                $host = trim((string)($_POST['host'] ?? '127.0.0.1'));
                $port = (int)($_POST['port'] ?? 3306);
                $name = trim((string)($_POST['name'] ?? ''));
                $user = trim((string)($_POST['user'] ?? ''));
                $pass = (string)($_POST['pass'] ?? '');
                if ($name === '') throw new RuntimeException('数据库名不能为空');
                $dsn  = "mysql:host=$host;port=$port;dbname=$name;charset=utf8mb4";
                new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
                $_SESSION['pc_install_db'] = compact('driver','host','port','name','user','pass');
            } else {
                $_SESSION['pc_install_db'] = ['driver' => 'sqlite'];
            }
            header('Location: install.php?step=3'); exit;
        } catch (Throwable $e) {
            $err = 'MySQL 连接失败：' . $e->getMessage();
        }
    }
    ob_start(); ?>
    <h2>数据库配置</h2>
    <p class="pc-desc">默认推荐使用 <b>SQLite</b>（零配置，单文件，自动写入 <code>data/auth.sqlite</code>）。<br>如果你有 MySQL 环境，也可以选择 MySQL。</p>
    <form method="post" class="pc-form">
      <input type="hidden" name="step" value="2">
      <input type="hidden" name="do" value="1">
      <label class="pc-radio">
        <input type="radio" name="driver" value="sqlite" <?= $driver==='sqlite'?'checked':'' ?> onclick="document.getElementById('mysqlbox').style.display='none'">
        <span>SQLite（推荐）</span>
      </label>
      <label class="pc-radio">
        <input type="radio" name="driver" value="mysql" <?= $driver==='mysql'?'checked':'' ?> onclick="document.getElementById('mysqlbox').style.display='block'">
        <span>MySQL</span>
      </label>
      <div id="mysqlbox" style="display:<?= $driver==='mysql'?'block':'none' ?>">
        <div class="pc-row"><label>主机</label><input name="host" value="<?= h((string)($_POST['host'] ?? '127.0.0.1')) ?>"></div>
        <div class="pc-row"><label>端口</label><input name="port" value="<?= h((string)($_POST['port'] ?? '3306')) ?>"></div>
        <div class="pc-row"><label>数据库</label><input name="name" value="<?= h((string)($_POST['name'] ?? '')) ?>"></div>
        <div class="pc-row"><label>用户</label><input name="user" value="<?= h((string)($_POST['user'] ?? '')) ?>"></div>
        <div class="pc-row"><label>密码</label><input name="pass" type="password"></div>
      </div>
      <button class="pc-btn">测试连接并继续 →</button>
    </form>
    <?php
    render('数据库配置', ob_get_clean(), 2, $err);
    exit;
}

/* -------------------- 步骤 3：管理员账号 -------------------- */
if ($step === 3) {
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
        $user = trim((string)($_POST['user'] ?? ''));
        $pass = (string)($_POST['pass'] ?? '');
        $pas2 = (string)($_POST['pas2'] ?? '');
        if (!preg_match('/^[A-Za-z0-9_\-]{3,32}$/', $user)) {
            $err = '用户名仅允许字母/数字/下划线/短横线，长度 3-32';
        } elseif (strlen($pass) < 8) {
            $err = '密码长度至少 8 位';
        } elseif ($pass !== $pas2) {
            $err = '两次输入的密码不一致';
        } else {
            $_SESSION['pc_install_admin'] = [
                'user' => $user,
                'hash' => password_hash($pass, PASSWORD_BCRYPT, ['cost' => 11]),
            ];
            header('Location: install.php?step=4'); exit;
        }
    }
    ob_start(); ?>
    <h2>创建管理员</h2>
    <p class="pc-desc">该账号用于登录后台、生成/管理激活码、查看设备与日志。</p>
    <form method="post" class="pc-form">
      <input type="hidden" name="step" value="3">
      <div class="pc-row"><label>用户名</label><input name="user" autocomplete="off" required></div>
      <div class="pc-row"><label>密码</label><input name="pass" type="password" minlength="8" required></div>
      <div class="pc-row"><label>确认密码</label><input name="pas2" type="password" minlength="8" required></div>
      <button class="pc-btn">创建并继续 →</button>
    </form>
    <?php
    render('管理员账号', ob_get_clean(), 3, $err);
    exit;
}

/* -------------------- 步骤 4：写入配置 + 建表 + 生成密钥 -------------------- */
if ($step === 4) {
    $db    = $_SESSION['pc_install_db']    ?? ['driver'=>'sqlite'];
    $admin = $_SESSION['pc_install_admin'] ?? null;
    if (!$admin) { header('Location: install.php?step=3'); exit; }

    // 1) 生成随机盐/密钥
    $baseSecret  = bin2hex(random_bytes(24));  // HMAC 握手密钥（首次激活共享）
    $cfgSalt     = bin2hex(random_bytes(16));  // 服务器派生盐

    // 2) 写入 config.php
    $cfgPhp = "<?php\nreturn " . var_export([
        'db'           => $db,
        'base_secret'  => $baseSecret,   // ★ 客户端需内嵌相同值（XOR 混淆存储）
        'salt'         => $cfgSalt,
        'api_version'  => 1,
        'ts_tolerance' => 300,           // 秒
        'session_ttl'  => 7 * 86400,     // 会话密钥有效期 7 天
        'min_client_ver' => '1.0.0',
        'notice'       => '欢迎使用 PersonalCenterUI，请遵守当地法律法规。',
    ], true) . ";\n";
    if (@file_put_contents($CFG, $cfgPhp) === false) {
        render('写入失败', '<p class="pc-alert err">无法写入 config.php，请检查目录权限。</p>', 4);
        exit;
    }

    // 3) 建表
    require __DIR__ . '/includes/db.php';
    require __DIR__ . '/includes/crypto.php';
    DB::ensureSchema();

    // 4) 写入管理员
    try {
        $st = DB::pdo()->prepare('INSERT INTO admins (username, password_hash, created_at) VALUES (?, ?, ?)');
        $st->execute([$admin['user'], $admin['hash'], time()]);
    } catch (Throwable $e) { /* 重装容忍 */ }

    // 5) 生成 RSA 密钥对
    [$priv, $pub] = Crypto::rsaGenerate();
    DB::setSetting('rsa_private', $priv);
    DB::setSetting('rsa_public',  $pub);
    DB::setSetting('install_at',  (string)time());

    // 6) 写入 install.lock
    @file_put_contents($LOCK, date('c'));

    // 7) 清掉 session
    unset($_SESSION['pc_install_db'], $_SESSION['pc_install_admin']);

    // 8) 展示"客户端嵌入所需参数"（仅此一次）
    $displayPub = trim($pub);
    ob_start(); ?>
    <h2>安装完成 🎉</h2>
    <p class="pc-desc">请把下面两个参数"一次性"嵌入到 iOS dylib 的 <code>PCAuthCrypto</code> 常量里（已做 XOR 混淆）：</p>

    <div class="pc-kv"><span class="k">BASE_SECRET</span>
      <code class="v"><?= h($baseSecret) ?></code></div>

    <div class="pc-kv"><span class="k">API 地址</span>
      <code class="v"><?= h((isset($_SERVER['HTTPS'])?'https://':'http://') . ($_SERVER['HTTP_HOST'] ?? 'your.host') . dirname($_SERVER['SCRIPT_NAME'] ?? '/') . '/api.php') ?></code></div>

    <div class="pc-kv block"><span class="k">RSA 公钥（PEM）</span>
      <pre class="v"><?= h($displayPub) ?></pre>
    </div>

    <p class="pc-desc small">⚠️ 本页关闭后无法再次查看 BASE_SECRET。RSA 公钥可随时在 <b>后台 → 密钥</b> 重新查看。</p>

    <a class="pc-btn" href="admin.php">前往管理后台 →</a>
    <?php
    render('完成', ob_get_clean(), 4, '', '安装成功，已生成 install.lock。');
    exit;
}
