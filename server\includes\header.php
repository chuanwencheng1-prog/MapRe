<?php
/**
 * 后台布局 - 头部（需 pc_require_login 之后 include）
 */
$_page = $_page ?? '';
$cfg = pc_cfg();
$u = pc_admin_user();
?>
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title><?= htmlspecialchars($cfg['site_name'] ?? '卡密授权系统') ?> - 后台</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="../assets/admin.css">
</head>
<body>
<div class="layout">
  <aside class="side">
    <div class="brand">🔐 卡密授权</div>
    <nav>
      <a href="dashboard.php" class="<?= $_page==='dash'?'active':'' ?>">📊 仪表盘</a>
      <a href="cards.php"     class="<?= $_page==='cards'?'active':'' ?>">🎫 卡密管理</a>
      <a href="generate.php"  class="<?= $_page==='gen'?'active':'' ?>">➕ 批量生成</a>
      <a href="devices.php"   class="<?= $_page==='dev'?'active':'' ?>">📱 设备管理</a>
      <a href="logs.php"      class="<?= $_page==='logs'?'active':'' ?>">📝 日志</a>
      <a href="settings.php"  class="<?= $_page==='set'?'active':'' ?>">⚙️ 系统设置</a>
    </nav>
    <div class="side-foot">
      <div class="user">👤 <?= htmlspecialchars($u['username'] ?? '') ?></div>
      <a class="logout" href="logout.php">退出</a>
    </div>
  </aside>
  <main class="main">
