<?php
/**
 * RSA 签名工具：服务器持有私钥，对响应做 SHA256WithRSA 签名
 */
require_once __DIR__ . '/db.php';

function pc_rsa_sign($message) {
    $priv = file_get_contents(pc_cfg('rsa_private'));
    if (!$priv) throw new Exception('私钥读取失败');
    $pkey = openssl_pkey_get_private($priv);
    if (!$pkey) throw new Exception('私钥解析失败');
    $sig = '';
    $ok = openssl_sign($message, $sig, $pkey, OPENSSL_ALGO_SHA256);
    if (!$ok) throw new Exception('RSA 签名失败');
    return base64_encode($sig);
}

function pc_rsa_public_pem() {
    $f = pc_cfg('rsa_public');
    return file_exists($f) ? file_get_contents($f) : '';
}
