//
//  PCAuthCrypto.h
//  PersonalCenterUI
//
//  底层加密工具：
//    · AES-256-CBC / PKCS#7    （CommonCrypto）
//    · HMAC-SHA256             （CommonCrypto）
//    · SHA-256 / URL-safe Base64
//    · RSA-2048 SHA256 签名验证（SecKey，配合服务端 openssl_sign）
//    · 关键字符串 XOR 混淆运行时解密（BASE_SECRET / API URL 绝不明文常量）
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PCAuthCrypto : NSObject

// ---- 混淆字符串运行时解码 ----
/// 取服务器 API 完整 URL（XOR 解混淆）
+ (NSString *)apiURL;
/// 取客户端/服务端共享的 BASE_SECRET（XOR 解混淆）
+ (NSString *)baseSecret;
/// 取 RSA 公钥 PEM（由服务器安装向导生成；粘贴到 .m 常量区）
+ (NSString *)rsaPublicPEM;

// ---- 基础算法 ----
+ (NSData *)sha256:(NSData *)data;
+ (NSData *)hmacSHA256:(NSData *)data key:(NSData *)key;
+ (NSString *)hexString:(NSData *)data;
+ (NSString *)b64uEncode:(NSData *)data;
+ (nullable NSData *)b64uDecode:(NSString *)s;

/// AES-256-CBC / PKCS#7。内部对 keyMaterial 做 SHA-256 派生 32 字节。
+ (nullable NSData *)aesEncrypt:(NSData *)plain keyMaterial:(NSString *)km iv:(NSData *)iv;
+ (nullable NSData *)aesDecrypt:(NSData *)cipher keyMaterial:(NSString *)km iv:(NSData *)iv;
+ (NSData *)randomBytes:(NSUInteger)len;

/// RSA-SHA256 验签：pemPublicKey 支持 "-----BEGIN PUBLIC KEY-----" 格式
+ (BOOL)verifyRSA:(NSData *)message signature:(NSData *)sig publicPEM:(NSString *)pem;

@end

NS_ASSUME_NONNULL_END
