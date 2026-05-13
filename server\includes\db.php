<?php
/**
 * 数据库连接工具（PDO 单例）
 */
if (!defined('PC_INC')) define('PC_INC', 1);

function pc_cfg($key = null) {
    static $cfg = null;
    if ($cfg === null) {
        $f = __DIR__ . '/config.php';
        if (!file_exists($f)) {
            header('Location: ' . dirname($_SERVER['PHP_SELF']) . '/../install.php');
            exit;
        }
        $cfg = require $f;
    }
    if ($key === null) return $cfg;
    return $cfg[$key] ?? null;
}

function pc_db() {
    static $pdo = null;
    if ($pdo !== null) return $pdo;
    $db = pc_cfg('db');
    $dsn = "mysql:host={$db['host']};port={$db['port']};dbname={$db['name']};charset=utf8mb4";
    $pdo = new PDO($dsn, $db['user'], $db['pass'], [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ]);
    return $pdo;
}

function pc_t($name) {
    $db = pc_cfg('db');
    return '`' . $db['pref'] . $name . '`';
}
