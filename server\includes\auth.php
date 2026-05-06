<?php
/**
 * PersonalCenterUI 网络验证 —— 管理员会话
 */
declare(strict_types=1);
if (!defined('PC_AUTH_ENTRY')) { http_response_code(403); exit('forbidden'); }

final class AdminAuth
{
    public static function start(): void
    {
        if (session_status() === PHP_SESSION_NONE) {
            session_set_cookie_params([
                'lifetime' => 0,
                'path'     => '/',
                'httponly' => true,
                'samesite' => 'Lax',
                'secure'   => !empty($_SERVER['HTTPS']),
            ]);
            session_name('PC_ADMIN');
            session_start();
        }
    }

    public static function login(string $user, string $pass): bool
    {
        self::start();
        $st = DB::pdo()->prepare('SELECT id, password_hash FROM admins WHERE username = ?');
        $st->execute([$user]);
        $r = $st->fetch();
        if (!$r || !password_verify($pass, (string)$r['password_hash'])) {
            DB::log('admin_login', 'fail', ['msg' => "user=$user"]);
            return false;
        }
        $_SESSION['admin_id']   = (int)$r['id'];
        $_SESSION['admin_user'] = $user;
        $_SESSION['csrf']       = bin2hex(random_bytes(16));
        DB::pdo()->prepare('UPDATE admins SET last_login_at = ?, last_ip = ? WHERE id = ?')
                 ->execute([time(), client_ip(), (int)$r['id']]);
        DB::log('admin_login', 'ok', ['msg' => "user=$user"]);
        return true;
    }

    public static function logout(): void
    {
        self::start();
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $p = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'] ?? '',
                      $p['secure'] ?? false, $p['httponly'] ?? false);
        }
        session_destroy();
    }

    public static function check(): void
    {
        self::start();
        if (empty($_SESSION['admin_id'])) {
            header('Location: admin.php?p=login');
            exit;
        }
    }

    public static function user(): string
    {
        self::start();
        return (string)($_SESSION['admin_user'] ?? '');
    }

    public static function csrf(): string
    {
        self::start();
        return (string)($_SESSION['csrf'] ?? '');
    }

    public static function csrfVerify(?string $token): bool
    {
        self::start();
        return !empty($token) && hash_equals((string)($_SESSION['csrf'] ?? ''), (string)$token);
    }
}
