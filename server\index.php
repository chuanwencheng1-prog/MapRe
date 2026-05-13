<?php
// 入口跳转
if (!file_exists(__DIR__ . '/includes/config.php')) {
    header('Location: install.php'); exit;
}
header('Location: admin/login.php'); exit;
