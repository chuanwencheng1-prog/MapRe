<?php
/**
 * PersonalCenterUI 网络验证 —— 通用辅助
 */
declare(strict_types=1);
if (!defined('PC_AUTH_ENTRY')) { http_response_code(403); exit('forbidden'); }

function h(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function client_ip(): string
{
    foreach (['HTTP_CF_CONNECTING_IP','HTTP_X_FORWARDED_FOR','REMOTE_ADDR'] as $k) {
        if (!empty($_SERVER[$k])) {
            $ip = trim(explode(',', (string)$_SERVER[$k])[0]);
            if (filter_var($ip, FILTER_VALIDATE_IP)) return $ip;
        }
    }
    return '0.0.0.0';
}

function json_out(array $data, int $code = 200): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function now(): int { return time(); }

function rand_code(int $len = 20): string
{
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   // 去除易混淆 0 O 1 I
    $n = strlen($chars);
    $out = '';
    for ($i = 0; $i < $len; $i++) {
        $out .= $chars[random_int(0, $n - 1)];
    }
    // 4-4-4-4-4 风格
    return substr(chunk_split($out, 4, '-'), 0, strlen($out) + intdiv($len - 1, 4));
}

/** 简易 IP 限流（基于 logs 表），每分钟最多 $limit 次 */
function rate_limit(string $action, int $limit = 30): bool
{
    $ip = client_ip();
    $since = now() - 60;
    $st = DB::pdo()->prepare('SELECT COUNT(*) c FROM logs WHERE ip = ? AND action = ? AND ts >= ?');
    $st->execute([$ip, $action, $since]);
    $row = $st->fetch();
    return ((int)($row['c'] ?? 0)) < $limit;
}

function nonce_consume(string $nonce, int $ttl = 600): bool
{
    try {
        // 清理过期
        DB::pdo()->prepare('DELETE FROM nonces WHERE created_at < ?')->execute([now() - $ttl]);
        $st = DB::pdo()->prepare('INSERT INTO nonces (nonce, created_at) VALUES (?, ?)');
        $st->execute([$nonce, now()]);
        return true;
    } catch (Throwable $e) {
        return false; // 主键冲突 = 重放
    }
}

function config_loaded(): bool
{
    return is_file(__DIR__ . '/../config.php') && is_file(__DIR__ . '/../install.lock');
}
