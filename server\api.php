<?php
/**
 * PersonalCenterUI 网络验证 —— 验证 API 入口
 *
 *  请求格式（POST application/json）：
 *    {
 *      "v":     1,
 *      "act":   "activate" | "heartbeat" | "query",
 *      "ts":    <unix seconds>,
 *      "nonce": <hex 16B>,
 *      "fp":    <device fingerprint>,
 *      "body":  base64url( AES-256-CBC( json(payload), K ) ),
 *      "iv":    base64url( iv16 ),
 *      "sig":   hex( HMAC-SHA256( v|act|ts|nonce|fp|body|iv, sharedKey ) )
 *    }
 *
 *  其中：
 *    · activate  的 sharedKey/K 使用 BASE_SECRET（握手）
 *    · heartbeat/query 的 sharedKey/K 使用 devices.session_key（首次激活成功后下发）
 *
 *  响应格式（成功）：
 *    {
 *      "ok":   true,
 *      "ts":   <server ts>,
 *      "body": base64url( AES( json(payload), K ) ),
 *      "iv":   base64url( iv ),
 *      "sig":  base64url( RSA-SHA256-Sign( sha256(body|iv), privateKey ) )
 *    }
 *
 *  失败响应（明文）：
 *    { "ok": false, "code": <errno>, "msg": "..." }
 *
 *  安全要素：
 *    ✓ 时间窗口（默认 ±300s）
 *    ✓ nonce 一次性（数据库防重放）
 *    ✓ HMAC 请求签名；RSA 响应签名（客户端内嵌公钥验签）
 *    ✓ IP 限流
 *    ✓ 设备指纹绑定卡密（首次激活即绑）
 *    ✓ 设备可被后台禁用
 */
declare(strict_types=1);
define('PC_AUTH_ENTRY', 1);

require __DIR__ . '/includes/helper.php';
if (!config_loaded()) { json_out(['ok'=>false,'code'=>5000,'msg'=>'server not installed'], 503); }

$cfg = require __DIR__ . '/config.php';
require __DIR__ . '/includes/db.php';
require __DIR__ . '/includes/crypto.php';

try {
    DB::pdo();
} catch (Throwable $e) {
    json_out(['ok'=>false,'code'=>5001,'msg'=>'db unavailable']);
}

/* ----------------- 请求解析 ----------------- */
$raw  = file_get_contents('php://input') ?: '';
$req  = json_decode($raw, true);
if (!is_array($req)) json_out(['ok'=>false,'code'=>4000,'msg'=>'bad request']);

$v     = (int)($req['v']     ?? 0);
$act   = (string)($req['act']   ?? '');
$ts    = (int)($req['ts']    ?? 0);
$nonce = (string)($req['nonce'] ?? '');
$fp    = (string)($req['fp']    ?? '');
$body  = (string)($req['body']  ?? '');
$iv    = (string)($req['iv']    ?? '');
$sig   = (string)($req['sig']   ?? '');

if ($v !== (int)$cfg['api_version'])          json_out(['ok'=>false,'code'=>4010,'msg'=>'version mismatch']);
if (!in_array($act, ['activate','heartbeat','query'], true))
                                              json_out(['ok'=>false,'code'=>4001,'msg'=>'bad act']);
if (!preg_match('/^[a-f0-9]{16,64}$/i', $nonce)) json_out(['ok'=>false,'code'=>4002,'msg'=>'bad nonce']);
if (strlen($fp) < 8 || strlen($fp) > 128)      json_out(['ok'=>false,'code'=>4003,'msg'=>'bad fp']);
if (!rate_limit($act, 60))                    json_out(['ok'=>false,'code'=>4290,'msg'=>'rate limited']);

$drift = abs(now() - $ts);
if ($drift > (int)$cfg['ts_tolerance'])        json_out(['ok'=>false,'code'=>4011,'msg'=>'clock drift']);

if (!nonce_consume($nonce))                    json_out(['ok'=>false,'code'=>4012,'msg'=>'replay']);

/* ----------------- 签名密钥判定 ----------------- */
$sharedKey = '';
$device    = null;
if ($act === 'activate') {
    $sharedKey = (string)$cfg['base_secret'];
} else {
    $st = DB::pdo()->prepare('SELECT * FROM devices WHERE fingerprint = ?');
    $st->execute([$fp]);
    $device = $st->fetch();
    if (!$device)                               json_out(['ok'=>false,'code'=>4040,'msg'=>'device not bound']);
    if ((int)$device['disabled'] === 1)         json_out(['ok'=>false,'code'=>4031,'msg'=>'device disabled']);
    if ((int)$device['session_expires_at'] < now())
                                                json_out(['ok'=>false,'code'=>4013,'msg'=>'session expired']);
    $sharedKey = (string)$device['session_key'];
}

/* ----------------- HMAC 校验 ----------------- */
$canonical = "$v|$act|$ts|$nonce|$fp|$body|$iv";
if (!Crypto::hmacVerify($canonical, $sharedKey, $sig)) {
    DB::log($act, 'sig_fail', ['fp'=>$fp]);
    json_out(['ok'=>false,'code'=>4030,'msg'=>'bad signature']);
}

/* ----------------- 解密 payload ----------------- */
$plain = Crypto::aesDecrypt($body, $iv, $sharedKey);
if ($plain === null)                           json_out(['ok'=>false,'code'=>4031,'msg'=>'decrypt fail']);
$payload = json_decode($plain, true);
if (!is_array($payload))                       json_out(['ok'=>false,'code'=>4032,'msg'=>'bad payload']);

/* ----------------- 业务处理 ----------------- */
$respond = function(array $data) use ($sharedKey) {
    global $cfg;
    $data['ts']    = now();
    $data['ok']    = true;
    $data['notice'] = (string)($cfg['notice'] ?? '');
    $enc = Crypto::aesEncrypt(json_encode($data, JSON_UNESCAPED_UNICODE), $sharedKey);
    $toSign = $enc['data'] . '|' . $enc['iv'];
    $priv   = DB::getSetting('rsa_private');
    $rsaSig = $priv ? Crypto::rsaSign(hash('sha256', $toSign, true), $priv) : '';
    json_out([
        'ok'   => true,
        'ts'   => now(),
        'body' => $enc['data'],
        'iv'   => $enc['iv'],
        'sig'  => $rsaSig,
    ]);
};

switch ($act) {
case 'activate':
    $code   = strtoupper(trim((string)($payload['code']   ?? '')));
    $model  = substr((string)($payload['model']  ?? ''), 0, 64);
    $system = substr((string)($payload['system'] ?? ''), 0, 64);
    $bundle = substr((string)($payload['bundle'] ?? ''), 0, 128);
    $ver    = substr((string)($payload['ver']    ?? ''), 0, 32);
    if ($code === '')                           json_out(['ok'=>false,'code'=>4100,'msg'=>'code required']);

    $pdo = DB::pdo();
    $pdo->beginTransaction();
    try {
        $st = $pdo->prepare('SELECT * FROM codes WHERE code = ?');
        $st->execute([$code]);
        $rec = $st->fetch();
        if (!$rec)              { $pdo->rollBack(); DB::log('activate','code_notfound',['fp'=>$fp,'code'=>$code]); json_out(['ok'=>false,'code'=>4101,'msg'=>'激活码不存在']); }
        if ((int)$rec['status'] === 2) { $pdo->rollBack(); json_out(['ok'=>false,'code'=>4102,'msg'=>'激活码已禁用']); }

        $nowT = now();
        // 已绑过
        if ((int)$rec['status'] === 1 && $rec['bound_fingerprint'] !== '') {
            if ($rec['bound_fingerprint'] !== $fp) {
                $pdo->rollBack();
                DB::log('activate','code_bound_other',['fp'=>$fp,'code'=>$code]);
                json_out(['ok'=>false,'code'=>4103,'msg'=>'激活码已被其它设备绑定']);
            }
            // 过期
            if ((int)$rec['expires_at'] > 0 && (int)$rec['expires_at'] < $nowT) {
                $pdo->rollBack();
                json_out(['ok'=>false,'code'=>4104,'msg'=>'激活码已过期']);
            }
        } else {
            // 首次绑定：设定过期时间
            $expires = $nowT + (int)$rec['duration_days'] * 86400;
            $pdo->prepare('UPDATE codes SET status=1, bound_fingerprint=?, first_bind_at=?, expires_at=? WHERE id=?')
                ->execute([$fp, $nowT, $expires, (int)$rec['id']]);
            $rec['expires_at']        = $expires;
            $rec['bound_fingerprint'] = $fp;
            $rec['status']            = 1;
        }

        // 为该设备生成会话密钥
        $sess    = bin2hex(random_bytes(32));
        $sessExp = $nowT + (int)$cfg['session_ttl'];

        // upsert device
        $st = $pdo->prepare('SELECT id, disabled FROM devices WHERE fingerprint = ?');
        $st->execute([$fp]);
        $d = $st->fetch();
        if ($d && (int)$d['disabled'] === 1) {
            $pdo->rollBack();
            DB::log('activate','device_disabled',['fp'=>$fp,'code'=>$code]);
            json_out(['ok'=>false,'code'=>4031,'msg'=>'设备已被禁用']);
        }
        if ($d) {
            $pdo->prepare('UPDATE devices SET bound_code_id=?, model=?, `system`=?, app_bundle=?, client_ver=?, last_seen=?, last_ip=?, session_key=?, session_expires_at=?, disabled=0 WHERE id=?')
                ->execute([(int)$rec['id'], $model, $system, $bundle, $ver, $nowT, client_ip(), $sess, $sessExp, (int)$d['id']]);
        } else {
            $pdo->prepare('INSERT INTO devices (fingerprint, bound_code_id, model, `system`, app_bundle, client_ver, last_seen, last_ip, disabled, session_key, session_expires_at, created_at) VALUES (?,?,?,?,?,?,?,?,0,?,?,?)')
                ->execute([$fp, (int)$rec['id'], $model, $system, $bundle, $ver, $nowT, client_ip(), $sess, $sessExp, $nowT]);
        }
        $pdo->prepare('UPDATE codes SET use_count = use_count + 1 WHERE id = ?')->execute([(int)$rec['id']]);
        $pdo->commit();

        DB::log('activate','ok',['fp'=>$fp,'code'=>$code]);
        $respond([
            'msg'                => '激活成功',
            'session_key'        => $sess,
            'session_expires_at' => $sessExp,
            'bound_until'        => (int)$rec['expires_at'],
            'level'              => (int)$rec['level'],
            'server_time'        => $nowT,
        ]);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        DB::log('activate','exception',['fp'=>$fp,'code'=>$code,'msg'=>$e->getMessage()]);
        json_out(['ok'=>false,'code'=>5100,'msg'=>'server error']);
    }
    break;

case 'heartbeat':
    $st = DB::pdo()->prepare('SELECT c.* FROM codes c WHERE c.id = ?');
    $st->execute([(int)$device['bound_code_id']]);
    $rec = $st->fetch();
    if (!$rec)                                   json_out(['ok'=>false,'code'=>4110,'msg'=>'未绑定有效激活码']);
    if ((int)$rec['status'] === 2)               json_out(['ok'=>false,'code'=>4111,'msg'=>'激活码已禁用']);
    if ($rec['bound_fingerprint'] !== $fp)       json_out(['ok'=>false,'code'=>4112,'msg'=>'设备指纹不匹配']);
    if ((int)$rec['expires_at'] > 0 && (int)$rec['expires_at'] < now())
                                                 json_out(['ok'=>false,'code'=>4113,'msg'=>'激活码已过期']);

    DB::pdo()->prepare('UPDATE devices SET last_seen = ?, last_ip = ?, client_ver = ? WHERE id = ?')
        ->execute([now(), client_ip(), substr((string)($payload['ver'] ?? ''), 0, 32), (int)$device['id']]);

    DB::log('heartbeat','ok',['fp'=>$fp]);
    $respond([
        'msg'                => 'alive',
        'bound_until'        => (int)$rec['expires_at'],
        'session_expires_at' => (int)$device['session_expires_at'],
        'level'              => (int)$rec['level'],
        'server_time'        => now(),
    ]);
    break;

case 'query':
    $st = DB::pdo()->prepare('SELECT * FROM codes WHERE id = ?');
    $st->execute([(int)$device['bound_code_id']]);
    $rec = $st->fetch();
    $respond([
        'bound_until'        => (int)($rec['expires_at'] ?? 0),
        'level'              => (int)($rec['level']      ?? 0),
        'session_expires_at' => (int)$device['session_expires_at'],
        'server_time'        => now(),
    ]);
    break;
}
