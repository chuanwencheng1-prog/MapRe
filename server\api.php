<?php
/**
 * iOS 客户端授权 API
 *
 * 接收：POST application/json
 *   {
 *     "app_id": "pcui_default",
 *     "action": "activate" | "verify",
 *     "card":    "XXXX-XXXX-XXXX-XXXX",
 *     "device_id":"<sha256 hex>",
 *     "device_info": { model, sys, name, bundle },
 *     "ts":     1710000000,
 *     "nonce":  "<hex>"
 *   }
 *
 * 返回：
 *   { "code":0, "msg":"ok", "data":{ "expires_at": <ts>, "sign":"<base64>" } }
 *
 *   sign = base64( RSA-SHA256-Sign( "app_id|device_id|card|expires_at", private_key ) )
 *
 * 错误码：
 *   1001 卡密不存在 / 格式错误
 *   1002 卡密已被禁用
 *   1003 卡密已过期
 *   1004 卡密已绑定其它设备
 *   1005 未激活（verify 时）
 *   1006 参数错误
 *   1007 APP_ID 不匹配
 *   1008 请求时间戳失效（防重放）
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') exit;

require_once __DIR__ . '/includes/db.php';
require_once __DIR__ . '/includes/rsa.php';
require_once __DIR__ . '/includes/functions.php';

function api_out($code, $msg, $data = []) {
    echo json_encode(['code'=>$code,'msg'=>$msg,'data'=>$data], JSON_UNESCAPED_UNICODE);
    exit;
}

/* ---------------- 请求解析 ---------------- */
$raw = file_get_contents('php://input');
$in  = json_decode($raw, true);
if (!is_array($in)) api_out(1006, '请求格式错误');

$app_id   = (string)($in['app_id']   ?? '');
$action   = (string)($in['action']   ?? '');
$card     = trim((string)($in['card'] ?? ''));
$deviceId = (string)($in['device_id'] ?? '');
$ts       = (int)($in['ts']          ?? 0);
$nonce    = (string)($in['nonce']    ?? '');
$devInfo  = is_array($in['device_info'] ?? null) ? $in['device_info'] : [];

if (!$app_id || !$action || !$deviceId) api_out(1006, '参数缺失');
if ($app_id !== pc_cfg('app_id'))       api_out(1007, 'APP_ID 不匹配');

// 防重放（±10 分钟）
if (abs(time() - $ts) > 600) api_out(1008, '时间戳失效');

/* ---------------- 业务处理 ---------------- */
try {
    $db = pc_db();

    // verify 动作若未传 card 认为是 1005
    if ($action === 'verify' && !$card) api_out(1005, '未激活');

    if (!$card) api_out(1001, '卡密为空');

    // 查卡密
    $row = $db->prepare("SELECT * FROM ".pc_t('cards')." WHERE card_key=? LIMIT 1");
    $row->execute([$card]);
    $c = $row->fetch();
    if (!$c) { pc_log('api_invalid', $card, $deviceId, 'not found'); api_out(1001, '卡密不存在'); }

    if ((int)$c['status'] === 2) { pc_log('api_disabled', $card, $deviceId); api_out(1002, '卡密已禁用'); }

    $now = time();
    // 分支：activate
    if ($action === 'activate') {
        if (!empty($c['device_id']) && $c['device_id'] !== $deviceId) {
            pc_log('api_devmiss', $card, $deviceId, ['bound'=>$c['device_id']]);
            api_out(1004, '卡密已绑定其它设备');
        }
        // 首次激活 → 绑定设备、计算到期时间
        if (empty($c['device_id'])) {
            $expires = $now + (int)$c['duration'];
            $up = $db->prepare("UPDATE ".pc_t('cards')." SET status=1,device_id=?,bound_at=?,expires_at=? WHERE id=?");
            $up->execute([$deviceId, $now, $expires, $c['id']]);
            $c['device_id']  = $deviceId;
            $c['bound_at']   = $now;
            $c['expires_at'] = $expires;
        } else {
            // 已绑同设备 → 续接返回现有到期
            if ((int)$c['expires_at'] <= $now) {
                // 若已过期，activate 视为失败
                $db->prepare("UPDATE ".pc_t('cards')." SET status=3 WHERE id=?")->execute([$c['id']]);
                pc_log('api_expired', $card, $deviceId);
                api_out(1003, '卡密已过期');
            }
        }
    }
    // 分支：verify
    elseif ($action === 'verify') {
        if (!$c['device_id']) { pc_log('api_nobound', $card, $deviceId); api_out(1005, '未激活'); }
        if ($c['device_id'] !== $deviceId) {
            pc_log('api_devmiss', $card, $deviceId, ['bound'=>$c['device_id']]);
            api_out(1004, '卡密已绑定其它设备');
        }
        if ((int)$c['expires_at'] <= $now) {
            $db->prepare("UPDATE ".pc_t('cards')." SET status=3 WHERE id=?")->execute([$c['id']]);
            pc_log('api_expired', $card, $deviceId);
            api_out(1003, '卡密已过期');
        }
    } else {
        api_out(1006, '未知 action');
    }

    /* ---------------- 更新设备心跳 ---------------- */
    $dev = $db->prepare("SELECT id FROM ".pc_t('devices')." WHERE device_id=?");
    $dev->execute([$deviceId]);
    $de = $dev->fetch();
    if ($de) {
        $db->prepare("UPDATE ".pc_t('devices')." SET last_seen=?,card_id=?,ip=?,model=?,sys=?,name=?,bundle=? WHERE id=?")
           ->execute([$now, $c['id'], pc_client_ip(),
                      substr($devInfo['model'] ?? '', 0, 60),
                      substr($devInfo['sys']   ?? '', 0, 30),
                      substr($devInfo['name']  ?? '', 0, 120),
                      substr($devInfo['bundle']?? '', 0, 120),
                      $de['id']]);
    } else {
        $db->prepare("INSERT INTO ".pc_t('devices')." (device_id,card_id,model,sys,name,bundle,ip,first_seen,last_seen,status) VALUES (?,?,?,?,?,?,?,?,?,1)")
           ->execute([$deviceId, $c['id'],
                      substr($devInfo['model'] ?? '', 0, 60),
                      substr($devInfo['sys']   ?? '', 0, 30),
                      substr($devInfo['name']  ?? '', 0, 120),
                      substr($devInfo['bundle']?? '', 0, 120),
                      pc_client_ip(), $now, $now]);
    }

    /* ---------------- RSA 签名响应 ---------------- */
    $expires = (int)$c['expires_at'];
    $msg = $app_id . '|' . $deviceId . '|' . $card . '|' . $expires;
    $sign = pc_rsa_sign($msg);

    pc_log('api_'.$action.'_ok', $card, $deviceId, ['exp'=>$expires]);
    api_out(0, 'ok', ['expires_at'=>$expires, 'sign'=>$sign, 'type'=>$c['type']]);

} catch (Exception $e) {
    pc_log('api_error', $card ?? '', $deviceId ?? '', $e->getMessage());
    api_out(500, '服务器异常');
}
