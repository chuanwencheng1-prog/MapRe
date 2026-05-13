<?php
/**
 * 通用工具：卡密生成、日志、时长解析等
 */
require_once __DIR__ . '/db.php';

/** 随机卡密（大小写+数字 + 每 4 位一个 '-'） */
function pc_gen_card($len = 16) {
    $alpha = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 去掉易混字符
    $out = '';
    for ($i = 0; $i < $len; $i++) $out .= $alpha[random_int(0, strlen($alpha)-1)];
    // 4-4-4-4 格式
    return implode('-', str_split($out, 4));
}

/** 类型 → 秒数 */
function pc_type_duration($type, $amount = 1) {
    $amount = max(1, (int)$amount);
    switch ($type) {
        case 'hour':  return 3600 * $amount;
        case 'day':   return 86400 * $amount;
        case 'week':  return 86400 * 7 * $amount;
        case 'month': return 86400 * 30 * $amount;
        case 'year':  return 86400 * 365 * $amount;
        case 'perm':  return 86400 * 365 * 100; // 永久 = 100 年
        default:      return 86400 * $amount;
    }
}

function pc_type_label($type) {
    return [
        'hour'=>'小时卡','day'=>'天卡','week'=>'周卡',
        'month'=>'月卡','year'=>'年卡','perm'=>'永久卡'
    ][$type] ?? $type;
}

function pc_client_ip() {
    foreach (['HTTP_X_FORWARDED_FOR','HTTP_X_REAL_IP','REMOTE_ADDR'] as $k) {
        if (!empty($_SERVER[$k])) {
            $ip = $_SERVER[$k];
            if (strpos($ip, ',') !== false) $ip = trim(explode(',', $ip)[0]);
            return $ip;
        }
    }
    return '';
}

function pc_log($type, $card = null, $device_id = null, $content = '') {
    try {
        $sql = "INSERT INTO ".pc_t('logs')." (type,card,device_id,ip,content,created_at) VALUES (?,?,?,?,?,?)";
        pc_db()->prepare($sql)->execute([
            $type, $card, $device_id, pc_client_ip(),
            is_string($content) ? $content : json_encode($content, JSON_UNESCAPED_UNICODE),
            time()
        ]);
    } catch (Exception $e) { /* ignore */ }
}

function pc_humantime($ts) {
    if (!$ts) return '-';
    return date('Y-m-d H:i:s', $ts);
}

function pc_left_human($exp) {
    if (!$exp) return '-';
    $d = $exp - time();
    if ($d <= 0) return '<span style="color:#e74c3c">已过期</span>';
    if ($d >= 86400) return floor($d/86400) . ' 天 ' . floor(($d%86400)/3600) . ' 小时';
    if ($d >= 3600)  return floor($d/3600) . ' 小时 ' . floor(($d%3600)/60) . ' 分钟';
    return floor($d/60) . ' 分钟';
}

function pc_status_label($s) {
    // 0=未用 1=已激活有效 2=已禁用 3=已过期
    $map = [0=>'<span class="pill pill-blue">未激活</span>',
            1=>'<span class="pill pill-green">已激活</span>',
            2=>'<span class="pill pill-red">已禁用</span>',
            3=>'<span class="pill pill-gray">已过期</span>'];
    return $map[$s] ?? $s;
}
