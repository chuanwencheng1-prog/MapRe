<?php
require_once __DIR__ . '/../includes/auth.php';
pc_admin_logout();
header('Location: login.php');
