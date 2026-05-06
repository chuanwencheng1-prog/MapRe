<?php
declare(strict_types=1);
define('PC_AUTH_ENTRY', 1);
require __DIR__ . '/includes/helper.php';
if (is_file(__DIR__ . '/config.php')) {
    require __DIR__ . '/includes/db.php';
    require __DIR__ . '/includes/auth.php';
    AdminAuth::logout();
}
header('Location: admin.php?p=login');
