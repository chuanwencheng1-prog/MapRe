<?php
/**
 * PersonalCenterUI 网络验证 —— 管理后台
 *   页面：login / dashboard / codes / devices / logs / keys / settings
 *   全部手机适配，统一 assets/style.css。
 */
declare(strict_types=1);
define('PC_AUTH_ENTRY', 1);

require __DIR__ . '/includes/helper.php';
if (!config_loaded()) { header('Location: install.php'); exit; }

require __DIR__ . '/includes/db.php';
require __DIR__ . '/includes/crypto.php';
require __DIR__ . '/includes/auth.php';

AdminAuth::start();

$p = (string)($_GET['p'] ?? 'dashboard');

/* -------------------- 登录页 -------------------- */
if ($p === 'login') {
    $err = '';
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
        if (!rate_limit('admin_login', 10)) $err = '尝试过于频繁，请稍后再试';
        else {
            $u = trim((string)($_POST['user'] ?? ''));
            $pw = (string)($_POST['pass'] ?? '');
            if (AdminAuth::login($u, $pw)) { header('Location: admin.php'); exit; }
            $err = '用户名或密码错误';
        }
    }
    ?><!doctype html><html><head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <title>登录 - PC 验证后台</title>
    <link rel="stylesheet" href="assets/style.css">
    </head><body class="pc-login">
    <div class="pc-card">
      <div class="pc-header" style="padding:0 0 12px">
        <div class="pc-logo">PersonalCenterUI · 后台</div>
        <div class="pc-sub">管理员登录</div>
      </div>
      <?php if ($err): ?><div class="pc-alert err"><?= h($err) ?></div><?php endif; ?>
      <form method="post" class="pc-form">
        <div class="pc-row"><label>用户名</label><input name="user" autocomplete="username" required></div>
        <div class="pc-row"><label>密码</label><input name="pass" type="password" autocomplete="current-password" required></div>
        <button class="pc-btn" style="width:100%">登 录</button>
      </form>
    </div>
    </body></html><?php
    exit;
}

AdminAuth::check();

/* -------------------- 通用布局 -------------------- */
function layout(string $title, string $body, string $on): void {
    $user = h(AdminAuth::user());
    ?><!doctype html><html><head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <title><?= h($title) ?> - PC 验证后台</title>
    <link rel="stylesheet" href="assets/style.css">
    </head><body>
    <div class="pc-wrap">
      <header class="pc-header" style="padding:12px 0">
        <div class="pc-logo">PC 验证 · 管理后台</div>
        <div class="pc-sub">登录用户：<?= $user ?></div>
      </header>
      <nav class="pc-nav">
        <?php
        $nav = [
          'dashboard' => '概览',
          'codes'     => '激活码',
          'devices'   => '设备',
          'logs'      => '日志',
          'keys'      => '密钥',
          'settings'  => '设置',
        ];
        foreach ($nav as $k=>$v) {
          $cls = $on === $k ? 'on' : '';
          echo "<a class=\"$cls\" href=\"admin.php?p=$k\">".h($v)."</a>";
        }
        ?>
        <a class="ghost" href="logout.php">退出</a>
      </nav>
      <?= $body ?>
      <footer class="pc-footer">© PersonalCenterUI Auth</footer>
    </div>
    </body></html><?php
}

/* -------------------- 仪表盘 -------------------- */
if ($p === 'dashboard') {
    $pdo = DB::pdo();
    $stat = [
        'codes_total'   => (int)$pdo->query('SELECT COUNT(*) c FROM codes')->fetch()['c'],
        'codes_bound'   => (int)$pdo->query('SELECT COUNT(*) c FROM codes WHERE status=1')->fetch()['c'],
        'devices'       => (int)$pdo->query('SELECT COUNT(*) c FROM devices')->fetch()['c'],
        'actives_24h'   => (int)$pdo->query('SELECT COUNT(*) c FROM devices WHERE last_seen>=' . (time()-86400))->fetch()['c'],
    ];
    $logs = $pdo->query('SELECT * FROM logs ORDER BY id DESC LIMIT 15')->fetchAll();
    ob_start(); ?>
    <div class="pc-grid">
      <div class="pc-stat"><div class="n"><?= $stat['codes_total'] ?></div><div class="l">激活码总数</div></div>
      <div class="pc-stat"><div class="n"><?= $stat['codes_bound'] ?></div><div class="l">已绑定</div></div>
      <div class="pc-stat"><div class="n"><?= $stat['devices'] ?></div><div class="l">设备数</div></div>
      <div class="pc-stat"><div class="n"><?= $stat['actives_24h'] ?></div><div class="l">24h 活跃</div></div>
    </div>
    <div class="pc-card">
      <h2>最近日志</h2>
      <div class="pc-scroll">
        <table class="pc-list">
          <tr><th>时间</th><th>动作</th><th>结果</th><th>指纹</th><th>IP</th><th>备注</th></tr>
          <?php foreach ($logs as $l): ?>
          <tr>
            <td><?= h(date('Y-m-d H:i:s', (int)$l['ts'])) ?></td>
            <td><?= h((string)$l['action']) ?></td>
            <td><span class="pc-pill <?= $l['result']==='ok'?'g':($l['result']==='fail'?'r':'y') ?>"><?= h((string)$l['result']) ?></span></td>
            <td><?= h(substr((string)$l['fingerprint'],0,16)) ?></td>
            <td><?= h((string)$l['ip']) ?></td>
            <td><?= h((string)$l['message']) ?></td>
          </tr>
          <?php endforeach; ?>
        </table>
      </div>
    </div>
    <?php
    layout('概览', ob_get_clean(), 'dashboard');
    exit;
}

/* -------------------- 激活码 -------------------- */
if ($p === 'codes') {
    $pdo = DB::pdo();
    $msg = ''; $err = '';

    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
        if (!AdminAuth::csrfVerify($_POST['csrf'] ?? null)) $err = 'CSRF 校验失败';
        else {
            $op = (string)($_POST['op'] ?? '');
            try {
                if ($op === 'gen') {
                    $count    = max(1, min(500, (int)($_POST['count']    ?? 1)));
                    $days     = max(1, min(3650, (int)($_POST['days']    ?? 30)));
                    $level    = max(0, min(9,    (int)($_POST['level']   ?? 1)));
                    $notes    = substr((string)($_POST['notes'] ?? ''), 0, 200);
                    $st = $pdo->prepare('INSERT INTO codes (code, status, level, duration_days, notes, created_at) VALUES (?, 0, ?, ?, ?, ?)');
                    for ($i=0; $i<$count; $i++) {
                        $c = rand_code(20);
                        for ($t=0; $t<5; $t++) {
                            try { $st->execute([$c, $level, $days, $notes, time()]); break; }
                            catch (Throwable $e) { $c = rand_code(20); }
                        }
                    }
                    $msg = "已生成 $count 个激活码";
                } elseif ($op === 'disable') {
                    $id = (int)($_POST['id'] ?? 0);
                    $pdo->prepare('UPDATE codes SET status=2 WHERE id=?')->execute([$id]);
                    $msg = '已禁用';
                } elseif ($op === 'enable') {
                    $id = (int)($_POST['id'] ?? 0);
                    $pdo->prepare("UPDATE codes SET status=CASE WHEN bound_fingerprint<>'' THEN 1 ELSE 0 END WHERE id=?")->execute([$id]);
                    $msg = '已启用';
                } elseif ($op === 'unbind') {
                    $id = (int)($_POST['id'] ?? 0);
                    $pdo->prepare('UPDATE codes SET status=0, bound_fingerprint="", first_bind_at=0, expires_at=0 WHERE id=?')->execute([$id]);
                    $msg = '已解绑';
                } elseif ($op === 'delete') {
                    $id = (int)($_POST['id'] ?? 0);
                    $pdo->prepare('DELETE FROM codes WHERE id=?')->execute([$id]);
                    $msg = '已删除';
                }
            } catch (Throwable $e) { $err = $e->getMessage(); }
        }
    }

    $q = trim((string)($_GET['q'] ?? ''));
    $where = '1=1'; $args = [];
    if ($q !== '') { $where .= ' AND (code LIKE ? OR notes LIKE ? OR bound_fingerprint LIKE ?)'; $args = ["%$q%","%$q%","%$q%"]; }
    $st = $pdo->prepare("SELECT * FROM codes WHERE $where ORDER BY id DESC LIMIT 200");
    $st->execute($args);
    $rows = $st->fetchAll();

    $csrf = h(AdminAuth::csrf());
    ob_start(); ?>
    <?php if ($msg): ?><div class="pc-alert ok"><?= h($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="pc-alert err"><?= h($err) ?></div><?php endif; ?>
    <div class="pc-card">
      <h2>生成激活码</h2>
      <form method="post" class="pc-form">
        <input type="hidden" name="csrf" value="<?= $csrf ?>">
        <input type="hidden" name="op" value="gen">
        <div class="pc-toolbar">
          <div class="pc-row"><label>数量</label><input name="count" type="number" min="1" max="500" value="10"></div>
          <div class="pc-row"><label>有效天数</label><input name="days" type="number" min="1" max="3650" value="30"></div>
          <div class="pc-row"><label>等级(0-9)</label><input name="level" type="number" min="0" max="9" value="1"></div>
          <div class="pc-row"><label>备注</label><input name="notes" placeholder="批次/渠道"></div>
          <div class="pc-row"><label>&nbsp;</label><button class="pc-btn accent">批量生成</button></div>
        </div>
      </form>
    </div>
    <div class="pc-card" style="margin-top:10px">
      <div class="pc-toolbar">
        <form method="get" class="pc-form">
          <input type="hidden" name="p" value="codes">
          <input name="q" value="<?= h($q) ?>" placeholder="搜索 code/备注/指纹">
          <button class="pc-btn ghost">搜索</button>
        </form>
      </div>
      <div class="pc-scroll">
      <table class="pc-list">
        <tr><th>激活码</th><th>状态</th><th>等级</th><th>天数</th><th>指纹</th><th>到期</th><th>使用</th><th>备注</th><th>操作</th></tr>
        <?php foreach ($rows as $r):
          $pill = ['y','g','r'][max(0,min(2,(int)$r['status']))];
          $st_lbl = ['未绑定','已绑定','已禁用'][max(0,min(2,(int)$r['status']))];
        ?>
        <tr>
          <td><code><?= h((string)$r['code']) ?></code></td>
          <td><span class="pc-pill <?= $pill ?>"><?= $st_lbl ?></span></td>
          <td><?= (int)$r['level'] ?></td>
          <td><?= (int)$r['duration_days'] ?></td>
          <td><?= h(substr((string)$r['bound_fingerprint'],0,14)) ?></td>
          <td><?= (int)$r['expires_at'] ? date('Y-m-d', (int)$r['expires_at']) : '-' ?></td>
          <td><?= (int)$r['use_count'] ?></td>
          <td><?= h((string)$r['notes']) ?></td>
          <td>
            <form method="post" style="display:inline">
              <input type="hidden" name="csrf" value="<?= $csrf ?>">
              <input type="hidden" name="id" value="<?= (int)$r['id'] ?>">
              <?php if ((int)$r['status'] === 2): ?>
                <button class="pc-btn ghost" name="op" value="enable">启用</button>
              <?php else: ?>
                <button class="pc-btn ghost" name="op" value="disable">禁用</button>
              <?php endif; ?>
              <button class="pc-btn ghost" name="op" value="unbind" onclick="return confirm('确定解绑?')">解绑</button>
              <button class="pc-btn danger" name="op" value="delete" onclick="return confirm('不可恢复，确定删除?')">删</button>
            </form>
          </td>
        </tr>
        <?php endforeach; ?>
      </table>
      </div>
    </div>
    <?php
    layout('激活码', ob_get_clean(), 'codes');
    exit;
}

/* -------------------- 设备 -------------------- */
if ($p === 'devices') {
    $pdo = DB::pdo();
    $msg = ''; $err = '';
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
        if (!AdminAuth::csrfVerify($_POST['csrf'] ?? null)) $err = 'CSRF 校验失败';
        else {
            $id = (int)($_POST['id'] ?? 0);
            $op = (string)($_POST['op'] ?? '');
            if ($op === 'disable') { $pdo->prepare('UPDATE devices SET disabled=1 WHERE id=?')->execute([$id]); $msg='已禁用'; }
            elseif ($op === 'enable') { $pdo->prepare('UPDATE devices SET disabled=0 WHERE id=?')->execute([$id]); $msg='已启用'; }
            elseif ($op === 'kick') { $pdo->prepare('UPDATE devices SET session_key="", session_expires_at=0 WHERE id=?')->execute([$id]); $msg='已踢出'; }
            elseif ($op === 'delete') { $pdo->prepare('DELETE FROM devices WHERE id=?')->execute([$id]); $msg='已删除'; }
        }
    }
    $q = trim((string)($_GET['q'] ?? ''));
    $where='1=1'; $args=[];
    if ($q !== '') { $where .= ' AND (fingerprint LIKE ? OR model LIKE ? OR app_bundle LIKE ?)'; $args=["%$q%","%$q%","%$q%"]; }
    $st = $pdo->prepare("SELECT d.*, c.code as c_code FROM devices d LEFT JOIN codes c ON c.id = d.bound_code_id WHERE $where ORDER BY d.last_seen DESC LIMIT 200");
    $st->execute($args);
    $rows = $st->fetchAll();
    $csrf = h(AdminAuth::csrf());
    ob_start(); ?>
    <?php if ($msg): ?><div class="pc-alert ok"><?= h($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="pc-alert err"><?= h($err) ?></div><?php endif; ?>
    <div class="pc-card">
      <div class="pc-toolbar">
        <form method="get" class="pc-form">
          <input type="hidden" name="p" value="devices">
          <input name="q" value="<?= h($q) ?>" placeholder="搜索 指纹/机型/包名">
          <button class="pc-btn ghost">搜索</button>
        </form>
      </div>
      <div class="pc-scroll">
      <table class="pc-list">
        <tr><th>指纹</th><th>机型</th><th>系统</th><th>包名</th><th>版本</th><th>绑定码</th><th>最后活跃</th><th>状态</th><th>操作</th></tr>
        <?php foreach ($rows as $r): ?>
        <tr>
          <td><?= h(substr((string)$r['fingerprint'],0,18)) ?></td>
          <td><?= h((string)$r['model']) ?></td>
          <td><?= h((string)$r['system']) ?></td>
          <td><?= h((string)$r['app_bundle']) ?></td>
          <td><?= h((string)$r['client_ver']) ?></td>
          <td><code><?= h((string)$r['c_code']) ?></code></td>
          <td><?= (int)$r['last_seen'] ? date('m-d H:i', (int)$r['last_seen']) : '-' ?></td>
          <td>
            <?php if ((int)$r['disabled'] === 1): ?><span class="pc-pill r">已禁用</span>
            <?php elseif ((int)$r['session_expires_at'] < time()): ?><span class="pc-pill y">会话过期</span>
            <?php else: ?><span class="pc-pill g">在线</span><?php endif; ?>
          </td>
          <td>
            <form method="post" style="display:inline">
              <input type="hidden" name="csrf" value="<?= $csrf ?>">
              <input type="hidden" name="id" value="<?= (int)$r['id'] ?>">
              <?php if ((int)$r['disabled'] === 1): ?>
                <button class="pc-btn ghost" name="op" value="enable">启用</button>
              <?php else: ?>
                <button class="pc-btn ghost" name="op" value="disable">禁用</button>
              <?php endif; ?>
              <button class="pc-btn ghost" name="op" value="kick">踢出</button>
              <button class="pc-btn danger" name="op" value="delete" onclick="return confirm('删除?')">删</button>
            </form>
          </td>
        </tr>
        <?php endforeach; ?>
      </table>
      </div>
    </div>
    <?php
    layout('设备', ob_get_clean(), 'devices');
    exit;
}

/* -------------------- 日志 -------------------- */
if ($p === 'logs') {
    $rows = DB::pdo()->query('SELECT * FROM logs ORDER BY id DESC LIMIT 500')->fetchAll();
    ob_start(); ?>
    <div class="pc-card">
      <h2>操作日志（最近 500 条）</h2>
      <div class="pc-scroll">
      <table class="pc-list">
        <tr><th>时间</th><th>动作</th><th>结果</th><th>code</th><th>指纹</th><th>IP</th><th>UA</th><th>备注</th></tr>
        <?php foreach ($rows as $l): ?>
        <tr>
          <td><?= h(date('m-d H:i:s', (int)$l['ts'])) ?></td>
          <td><?= h((string)$l['action']) ?></td>
          <td><span class="pc-pill <?= $l['result']==='ok'?'g':($l['result']==='fail'?'r':'y') ?>"><?= h((string)$l['result']) ?></span></td>
          <td><code><?= h(substr((string)$l['code'],0,12)) ?></code></td>
          <td><?= h(substr((string)$l['fingerprint'],0,14)) ?></td>
          <td><?= h((string)$l['ip']) ?></td>
          <td><?= h(substr((string)$l['ua'],0,28)) ?></td>
          <td><?= h((string)$l['message']) ?></td>
        </tr>
        <?php endforeach; ?>
      </table>
      </div>
    </div>
    <?php
    layout('日志', ob_get_clean(), 'logs');
    exit;
}

/* -------------------- 密钥 -------------------- */
if ($p === 'keys') {
    $pub  = DB::getSetting('rsa_public');
    $cfg  = require __DIR__ . '/config.php';
    $base = (isset($_SERVER['HTTPS'])?'https://':'http://') . ($_SERVER['HTTP_HOST'] ?? 'your.host') . dirname($_SERVER['SCRIPT_NAME'] ?? '/');
    ob_start(); ?>
    <div class="pc-card">
      <h2>客户端接入参数</h2>
      <div class="pc-kv"><span class="k">API 地址</span><code class="v"><?= h($base . '/api.php') ?></code></div>
      <div class="pc-kv"><span class="k">API 版本</span><code class="v"><?= (int)$cfg['api_version'] ?></code></div>
      <div class="pc-kv"><span class="k">时间窗口（秒）</span><code class="v"><?= (int)$cfg['ts_tolerance'] ?></code></div>
      <div class="pc-kv block"><span class="k">RSA 公钥 (PEM) — 粘贴到 PCAuthCrypto.m</span><pre class="v"><?= h(trim((string)$pub)) ?></pre></div>
      <p class="pc-desc small">BASE_SECRET 出于安全考虑不再可见，如遗失请重新安装或在 config.php 中手动读取。</p>
    </div>
    <?php
    layout('密钥', ob_get_clean(), 'keys');
    exit;
}

/* -------------------- 设置 -------------------- */
if ($p === 'settings') {
    $cfgPath = __DIR__ . '/config.php';
    $cfg     = require $cfgPath;
    $msg = ''; $err = '';
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
        if (!AdminAuth::csrfVerify($_POST['csrf'] ?? null)) $err = 'CSRF 校验失败';
        else {
            $cfg['notice']         = substr((string)($_POST['notice'] ?? ''), 0, 500);
            $cfg['min_client_ver'] = substr((string)($_POST['min_client_ver'] ?? '1.0.0'), 0, 32);
            $cfg['ts_tolerance']   = max(30, min(3600, (int)($_POST['ts_tolerance'] ?? 300)));
            $cfg['session_ttl']    = max(3600, min(30*86400, (int)($_POST['session_ttl'] ?? 7*86400)));
            $php = "<?php\nreturn " . var_export($cfg, true) . ";\n";
            if (@file_put_contents($cfgPath, $php) !== false) $msg = '已保存';
            else $err = '写入 config.php 失败，请检查权限';
        }
    }
    $csrf = h(AdminAuth::csrf());
    ob_start(); ?>
    <?php if ($msg): ?><div class="pc-alert ok"><?= h($msg) ?></div><?php endif; ?>
    <?php if ($err): ?><div class="pc-alert err"><?= h($err) ?></div><?php endif; ?>
    <div class="pc-card">
      <h2>服务端设置</h2>
      <form method="post" class="pc-form">
        <input type="hidden" name="csrf" value="<?= $csrf ?>">
        <div class="pc-row"><label>通知公告（下发给客户端显示）</label><input name="notice" value="<?= h((string)$cfg['notice']) ?>"></div>
        <div class="pc-row"><label>最低客户端版本</label><input name="min_client_ver" value="<?= h((string)$cfg['min_client_ver']) ?>"></div>
        <div class="pc-row"><label>请求时间窗口（秒，建议 300）</label><input name="ts_tolerance" type="number" value="<?= (int)$cfg['ts_tolerance'] ?>"></div>
        <div class="pc-row"><label>会话密钥 TTL（秒，默认 7 天）</label><input name="session_ttl" type="number" value="<?= (int)$cfg['session_ttl'] ?>"></div>
        <button class="pc-btn">保存</button>
      </form>
    </div>
    <?php
    layout('设置', ob_get_clean(), 'settings');
    exit;
}

header('Location: admin.php?p=dashboard');
