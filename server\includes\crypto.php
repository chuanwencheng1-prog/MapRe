<?php
/**
 * PersonalCenterUI 网络验证 —— 加密工具
 *   - AES-256-CBC（PKCS#7）
 *   - HMAC-SHA256 请求/响应签名
 *   - RSA-2048（OpenSSL）生成密钥对 + 私钥 SHA256 签名，客户端公钥验签
 *   - 常量时间比较、URL-safe base64
 */
declare(strict_types=1);
if (!defined('PC_AUTH_ENTRY')) { http_response_code(403); exit('forbidden'); }

final class Crypto
{
    public static function b64u_encode(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }

    public static function b64u_decode(string $s): string
    {
        $s = strtr($s, '-_', '+/');
        $pad = strlen($s) % 4;
        if ($pad) $s .= str_repeat('=', 4 - $pad);
        return base64_decode($s, true) ?: '';
    }

    public static function randHex(int $bytes = 16): string
    {
        return bin2hex(random_bytes($bytes));
    }

    /** AES-256-CBC 加密（PKCS#7），密钥为任意长度字符串，内部 SHA-256 派生 32 字节。 */
    public static function aesEncrypt(string $plain, string $keyMaterial): array
    {
        $key = hash('sha256', $keyMaterial, true);
        $iv  = random_bytes(16);
        $ct  = openssl_encrypt($plain, 'aes-256-cbc', $key, OPENSSL_RAW_DATA, $iv);
        if ($ct === false) throw new RuntimeException('aes encrypt failed');
        return [
            'data' => self::b64u_encode($ct),
            'iv'   => self::b64u_encode($iv),
        ];
    }

    public static function aesDecrypt(string $dataB64u, string $ivB64u, string $keyMaterial): ?string
    {
        $key = hash('sha256', $keyMaterial, true);
        $ct  = self::b64u_decode($dataB64u);
        $iv  = self::b64u_decode($ivB64u);
        if (strlen($iv) !== 16 || $ct === '') return null;
        $pt  = openssl_decrypt($ct, 'aes-256-cbc', $key, OPENSSL_RAW_DATA, $iv);
        return $pt === false ? null : $pt;
    }

    public static function hmac(string $payload, string $secret): string
    {
        return hash_hmac('sha256', $payload, $secret);
    }

    public static function hmacVerify(string $payload, string $secret, string $expectedHex): bool
    {
        $calc = self::hmac($payload, $secret);
        return hash_equals($calc, $expectedHex);
    }

    /** RSA-2048 密钥对生成，返回 [privatePEM, publicPEM]。 */
    public static function rsaGenerate(): array
    {
        $res = openssl_pkey_new([
            'private_key_bits' => 2048,
            'private_key_type' => OPENSSL_KEYTYPE_RSA,
        ]);
        if (!$res) throw new RuntimeException('openssl_pkey_new failed');
        openssl_pkey_export($res, $priv);
        $pub = openssl_pkey_get_details($res)['key'] ?? '';
        return [$priv, $pub];
    }

    /** 用私钥对消息做 SHA256 签名，返回 base64url。 */
    public static function rsaSign(string $msg, string $privatePem): string
    {
        $ok = openssl_sign($msg, $sig, $privatePem, OPENSSL_ALGO_SHA256);
        if (!$ok) throw new RuntimeException('openssl_sign failed');
        return self::b64u_encode($sig);
    }

    /** 导出仅包含公钥模数/指数的 DER bytes（客户端 SecKey 友好，可选使用）。 */
    public static function rsaPublicDer(string $publicPem): string
    {
        $res = openssl_pkey_get_public($publicPem);
        if (!$res) return '';
        $det = openssl_pkey_get_details($res);
        return $det['key'] ?? '';
    }
}
