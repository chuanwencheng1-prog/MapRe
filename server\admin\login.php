<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/functions.php';

$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $u = trim($_POST['username'] ?? '');
    $p = (string)($_POST['password'] ?? '');
    if (pc_admin_login($u, $p)) {
        pc_log('admin_login', null, null, ['user'=>$u]);
        header('Location: dashboard.php'); exit;
    }
    $err = '账号或密码错误';
}

if (pc_admin_user()) { header('Location: dashboard.php'); exit; }
$cfg = pc_cfg();
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title><?= htmlspecialchars($cfg['site_name']) ?> - 登录</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="../assets/admin.css">
</head>
<body class="login-page">
<div class="login-wrap">
  <div class="login-box">
    <div class="login-hd">
      <h1>🔐 <?= htmlspecialchars($cfg['site_name']) ?></h1>
      <p>后台管理登录</p>
    </div>
    <form method="post" class="login-form">
      <?php if ($err): ?><div class="err"><?= htmlspecialchars($err) ?></div><?php endif; ?>
      <div class="field"><label>账号</label><input name="username" required autofocus></div>
      <div class="field"><label>密码</label><input name="password" type="password" required></div>
      <button class="btn" type="submit">登 录</button>
    </form>
    <p class="login-foot">© <?= date('Y') ?> <?= htmlspecialchars($cfg['site_name']) ?></p>
  </div>
</div>
</body>
</html>
