<?php
/**
 * PersonalCenterUI 网络验证 —— PDO 数据库封装
 * 支持 SQLite（默认、零依赖）与 MySQL。
 */
declare(strict_types=1);
if (!defined('PC_AUTH_ENTRY')) { http_response_code(403); exit('forbidden'); }

final class DB
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo) return self::$pdo;
        $cfg = require __DIR__ . '/../config.php';
        if (($cfg['db']['driver'] ?? 'sqlite') === 'mysql') {
            $dsn = sprintf(
                'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
                $cfg['db']['host'] ?? '127.0.0.1',
                (int)($cfg['db']['port'] ?? 3306),
                $cfg['db']['name'] ?? ''
            );
            self::$pdo = new PDO($dsn, $cfg['db']['user'] ?? '', $cfg['db']['pass'] ?? '', [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
            ]);
        } else {
            $file = $cfg['db']['sqlite_path'] ?? (__DIR__ . '/../data/auth.sqlite');
            @mkdir(dirname($file), 0700, true);
            self::$pdo = new PDO('sqlite:' . $file, null, null, [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]);
            self::$pdo->exec('PRAGMA journal_mode = WAL;');
            self::$pdo->exec('PRAGMA foreign_keys = ON;');
        }
        return self::$pdo;
    }

    public static function driver(): string
    {
        return self::pdo()->getAttribute(PDO::ATTR_DRIVER_NAME);
    }

    /** 初始化全部表结构（install 与 api/admin 均可安全重复调用，IF NOT EXISTS）。 */
    public static function ensureSchema(): void
    {
        $p  = self::pdo();
        $ai = self::driver() === 'mysql' ? 'INT AUTO_INCREMENT PRIMARY KEY' : 'INTEGER PRIMARY KEY AUTOINCREMENT';
        $ts = self::driver() === 'mysql' ? 'BIGINT' : 'INTEGER';

        $p->exec("CREATE TABLE IF NOT EXISTS admins (
            id $ai,
            username VARCHAR(64) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            created_at $ts NOT NULL,
            last_login_at $ts DEFAULT 0,
            last_ip VARCHAR(64) DEFAULT ''
        )");

        $p->exec("CREATE TABLE IF NOT EXISTS codes (
            id $ai,
            code VARCHAR(64) UNIQUE NOT NULL,
            status INTEGER NOT NULL DEFAULT 0,
            level INTEGER NOT NULL DEFAULT 1,
            duration_days INTEGER NOT NULL DEFAULT 30,
            bound_fingerprint VARCHAR(128) DEFAULT '',
            first_bind_at $ts DEFAULT 0,
            expires_at $ts DEFAULT 0,
            use_count INTEGER NOT NULL DEFAULT 0,
            notes VARCHAR(255) DEFAULT '',
            created_at $ts NOT NULL
        )");

        $p->exec("CREATE TABLE IF NOT EXISTS devices (
            id $ai,
            fingerprint VARCHAR(128) UNIQUE NOT NULL,
            bound_code_id INTEGER DEFAULT 0,
            model VARCHAR(64) DEFAULT '',
            `system` VARCHAR(64) DEFAULT '',
            app_bundle VARCHAR(128) DEFAULT '',
            client_ver VARCHAR(32) DEFAULT '',
            last_seen $ts DEFAULT 0,
            last_ip VARCHAR(64) DEFAULT '',
            disabled INTEGER NOT NULL DEFAULT 0,
            session_key VARCHAR(128) DEFAULT '',
            session_expires_at $ts DEFAULT 0,
            created_at $ts NOT NULL
        )");

        $p->exec("CREATE TABLE IF NOT EXISTS nonces (
            nonce VARCHAR(64) PRIMARY KEY,
            created_at $ts NOT NULL
        )");

        $p->exec("CREATE TABLE IF NOT EXISTS logs (
            id $ai,
            ts $ts NOT NULL,
            action VARCHAR(32) NOT NULL,
            code VARCHAR(64) DEFAULT '',
            fingerprint VARCHAR(128) DEFAULT '',
            ip VARCHAR(64) DEFAULT '',
            ua VARCHAR(255) DEFAULT '',
            result VARCHAR(32) DEFAULT '',
            message VARCHAR(255) DEFAULT ''
        )");

        $p->exec("CREATE TABLE IF NOT EXISTS settings (
            k VARCHAR(64) PRIMARY KEY,
            v TEXT NOT NULL
        )");
    }

    public static function getSetting(string $k, string $default = ''): string
    {
        $st = self::pdo()->prepare('SELECT v FROM settings WHERE k = ?');
        $st->execute([$k]);
        $r = $st->fetch();
        return $r ? (string)$r['v'] : $default;
    }

    public static function setSetting(string $k, string $v): void
    {
        $drv = self::driver();
        if ($drv === 'mysql') {
            $sql = 'INSERT INTO settings (k,v) VALUES (?,?) ON DUPLICATE KEY UPDATE v = VALUES(v)';
        } else {
            $sql = 'INSERT INTO settings (k,v) VALUES (?,?) ON CONFLICT(k) DO UPDATE SET v = excluded.v';
        }
        self::pdo()->prepare($sql)->execute([$k, $v]);
    }

    public static function log(string $action, string $result, array $ctx = []): void
    {
        try {
            $st = self::pdo()->prepare(
                'INSERT INTO logs (ts,action,code,fingerprint,ip,ua,result,message) VALUES (?,?,?,?,?,?,?,?)'
            );
            $st->execute([
                time(),
                $action,
                (string)($ctx['code'] ?? ''),
                (string)($ctx['fp']   ?? ''),
                (string)($_SERVER['REMOTE_ADDR'] ?? ''),
                substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 255),
                $result,
                substr((string)($ctx['msg'] ?? ''), 0, 255),
            ]);
        } catch (Throwable $e) { /* 日志失败静默 */ }
    }
}
