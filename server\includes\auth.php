<?php
/**
 * 后台管理员登录态
 */
require_once __DIR__ . '/db.php';

if (session_status() === PHP_SESSION_NONE) {
    session_name('PCAUTHSID');
    session_start();
}

function pc_admin_login($username, $password) {
    $row = pc_db()->prepare("SELECT * FROM ".pc_t('admin')." WHERE username=? LIMIT 1");
    $row->execute([$username]);
    $u = $row->fetch();
    if (!$u) return false;
    if (!password_verify($password, $u['password'])) return false;
    $_SESSION['pc_admin'] = ['id'=>$u['id'],'username'=>$u['username'],'t'=>time()];
    return true;
}

function pc_admin_logout() {
    unset($_SESSION['pc_admin']);
    session_destroy();
}

function pc_admin_user() {
    return $_SESSION['pc_admin'] ?? null;
}

function pc_require_login() {
    if (!pc_admin_user()) {
        $base = rtrim(dirname($_SERVER['PHP_SELF']), '/\\');
        // 如果已经在 admin/ 目录下
        if (strpos($_SERVER['PHP_SELF'], '/admin/') !== false) {
            header('Location: login.php'); exit;
        }
        header('Location: admin/login.php'); exit;
    }
}

function pc_csrf() {
    if (empty($_SESSION['csrf'])) $_SESSION['csrf'] = bin2hex(random_bytes(16));
    return $_SESSION['csrf'];
}

function pc_check_csrf() {
    $t = $_POST['_csrf'] ?? $_GET['_csrf'] ?? '';
    if (!$t || !hash_equals($_SESSION['csrf'] ?? '', $t)) {
        http_response_code(403); die('CSRF 校验失败');
    }
}
