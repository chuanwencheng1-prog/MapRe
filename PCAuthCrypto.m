//
//  PCAuthCrypto.m
//  PersonalCenterUI
//

#import "PCAuthCrypto.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

// ============================================================================
// ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
//                       接 入 参 数 填 写 区
//    (由服务器 install.php 安装完成后的"完成页"给出；请填入下面三项)
// ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
// ============================================================================
//
//  防破解思路：
//    ·《API 地址》和《BASE_SECRET》不以明文常量出现在 __TEXT 段中；
//      编译期把每一位异或 0x5A，运行时才 XOR 回明文。
//      strings / otool / hopper 扫描二进制将看不到完整 URL/密钥。
//    · RSA 公钥明文放置是安全的（公钥本来就是公开的）；
//      但篡改它会导致签名验签失败，客户端将拒绝服务器响应。
//
//  一次性生成 XOR 字节数组的小工具（Python 3，任意系统都能跑）：
//
//      python3 -c "s='你的明文'; print(','.join(f'0x{b^0x5A:02x}' for b in s.encode()))"
//
//  把输出直接粘到下面两个数组里即可。

// ─── ① API 地址（XOR 混淆）─────────────────────────────────────────────────
//
//  明文："http://38.76.212.184:7873/api.php"
//
static const unsigned char kPC_ApiURL_XOR[] = {
    0x32,0x2e,0x2e,0x2a,0x60,0x75,0x75,0x69,0x62,0x74,0x6d,0x6c,0x74,0x68,0x6b,0x68,
    0x74,0x6b,0x62,0x6e,0x60,0x6d,0x62,0x6d,0x69,0x75,0x75,0x3b,0x2a,0x33,0x74,0x2a,
    0x32,0x2a
};

// ─── ② BASE_SECRET（XOR 混淆）──────────────────────────────────────────────
//
//  明文："35d6055da43facec63c315e43a8492f73143db14c00c5970"（48 位 hex）
//
static const unsigned char kPC_BaseSecret_XOR[] = {
    0x69,0x6f,0x3e,0x6c,0x6a,0x6f,0x6f,0x3e,0x3b,0x6e,0x69,0x3c,0x3b,0x39,0x3f,0x39,
    0x6c,0x69,0x39,0x69,0x6b,0x6f,0x3f,0x6e,0x69,0x3b,0x62,0x6e,0x63,0x68,0x3c,0x6d,
    0x69,0x6b,0x6e,0x69,0x3e,0x38,0x6b,0x6e,0x39,0x6a,0x6a,0x39,0x6f,0x63,0x6d,0x6a
};


// XOR 掩码（可按需改，同步改生成脚本中的 0x5A）
static const unsigned char kPC_XOR_MASK = 0x5A;

// ─── ③ RSA 公钥 PEM ───────────────────────────────────────────────────────
//     从服务端 "后台 → 密钥" 页复制整块 PEM（含 BEGIN/END 行）粘贴到这里。
static NSString *const kPC_RSA_PublicKeyPEM = @""
"-----BEGIN PUBLIC KEY-----\n"
"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu/hurCDXDSb5K1Nim3a9\n"
"xy4HKUjZIxY1N/qAdUUWYVpePySmyBOA0xD3HnPIRVogTOQMJpXShS5l2UGlfulT\n"
"adQfDzuOCVvv12RBDUfo7evSZrXP/X9nUESzF6mcKLiFlgGloVwxO3zsisZPLvC6\n"
"jHKmzEAp0kNc9WZieI+YsVsTHbp+B2RTqBPctF5WvS6V59CkO8ISL+iuKOtd65Rb\n"
"CuQyDIV/qsnn2CxzvjFgL0pOHHAnW5yI3itcoG+JxTcmITy7I1T/WTLtZLhqZAyW\n"
"lC+HkpkRCkslb6SaNtjdYFZBPcmo1dIe71vPhbM3dAP0g2DZqp4lL0J6C0QRMEFv\n"
"qwIDAQAB\n"
"-----END PUBLIC KEY-----\n";
// ============================================================================

static NSString *PC_XOR_Decode(const unsigned char *bytes, size_t len) {
    if (len == 0 || len > 512) return @"";
    char buf[513];
    for (size_t i = 0; i < len; i++) buf[i] = (char)(bytes[i] ^ kPC_XOR_MASK);
    buf[len] = 0;
    return [NSString stringWithUTF8String:buf] ?: @"";
}

@implementation PCAuthCrypto

+ (NSString *)apiURL      { return PC_XOR_Decode(kPC_ApiURL_XOR,      sizeof(kPC_ApiURL_XOR));      }
+ (NSString *)baseSecret  { return PC_XOR_Decode(kPC_BaseSecret_XOR,  sizeof(kPC_BaseSecret_XOR));  }
+ (NSString *)rsaPublicPEM{ return kPC_RSA_PublicKeyPEM; }

#pragma mark - Digest / HMAC / Hex / Base64

+ (NSData *)sha256:(NSData *)data {
    unsigned char out[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, out);
    return [NSData dataWithBytes:out length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSData *)hmacSHA256:(NSData *)data key:(NSData *)key {
    unsigned char out[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, out);
    return [NSData dataWithBytes:out length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSString *)hexString:(NSData *)data {
    static const char *hx = "0123456789abcdef";
    const unsigned char *b = data.bytes;
    NSUInteger n = data.length;
    char *buf = (char *)malloc(n * 2 + 1);
    for (NSUInteger i = 0; i < n; i++) {
        buf[i*2]   = hx[b[i] >> 4];
        buf[i*2+1] = hx[b[i] & 0x0F];
    }
    buf[n*2] = 0;
    NSString *s = [NSString stringWithUTF8String:buf];
    free(buf);
    return s ?: @"";
}

+ (NSString *)b64uEncode:(NSData *)data {
    NSString *s = [data base64EncodedStringWithOptions:0];
    s = [s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    s = [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return s;
}

+ (NSData *)b64uDecode:(NSString *)s {
    NSMutableString *m = [s mutableCopy];
    [m replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0,m.length)];
    [m replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0,m.length)];
    NSInteger pad = (4 - (m.length % 4)) % 4;
    for (NSInteger i = 0; i < pad; i++) [m appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:m options:0];
}

+ (NSData *)randomBytes:(NSUInteger)len {
    NSMutableData *d = [NSMutableData dataWithLength:len];
    (void)SecRandomCopyBytes(kSecRandomDefault, len, d.mutableBytes);
    return d;
}

#pragma mark - AES-256-CBC / PKCS#7

+ (NSData *)_cryptAES:(CCOperation)op data:(NSData *)data km:(NSString *)km iv:(NSData *)iv {
    if (iv.length != kCCBlockSizeAES128) return nil;

    // 派生 32 字节密钥
    NSData *kmData = [km dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char key[32];
    CC_SHA256(kmData.bytes, (CC_LONG)kmData.length, key);

    size_t outLen = data.length + kCCBlockSizeAES128;
    NSMutableData *out = [NSMutableData dataWithLength:outLen];
    size_t moved = 0;
    CCCryptorStatus s = CCCrypt(op,
                                kCCAlgorithmAES,
                                kCCOptionPKCS7Padding,
                                key, kCCKeySizeAES256,
                                iv.bytes,
                                data.bytes, data.length,
                                out.mutableBytes, outLen, &moved);
    if (s != kCCSuccess) return nil;
    out.length = moved;
    return out;
}

+ (NSData *)aesEncrypt:(NSData *)plain keyMaterial:(NSString *)km iv:(NSData *)iv {
    return [self _cryptAES:kCCEncrypt data:plain km:km iv:iv];
}
+ (NSData *)aesDecrypt:(NSData *)cipher keyMaterial:(NSString *)km iv:(NSData *)iv {
    return [self _cryptAES:kCCDecrypt data:cipher km:km iv:iv];
}

#pragma mark - RSA 公钥验签

/// 把 PEM 字符串（-----BEGIN PUBLIC KEY-----...）导入为 SecKeyRef
+ (SecKeyRef)_createSecKeyWithPEM:(NSString *)pem CF_RETURNS_RETAINED {
    NSString *b64 = [pem stringByReplacingOccurrencesOfString:@"-----BEGIN PUBLIC KEY-----" withString:@""];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"-----END PUBLIC KEY-----" withString:@""];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    b64 = [b64 stringByReplacingOccurrencesOfString:@" "  withString:@""];
    NSData *der = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (der.length == 0) return NULL;

    // der 是 SubjectPublicKeyInfo，需要剥去 SPKI 头以得到 PKCS#1 RSAPublicKey，
    // 再用 SecKeyCreateWithData(kSecAttrKeyTypeRSA) 导入。这里用 Sec 原生 API
    // 支持的一条相对可靠路径：将 SPKI 解析出 BITSTRING 内容。
    const unsigned char *p = der.bytes;
    NSUInteger len = der.length;

    // 粗解析：寻找 "03 81/82 XX 00 30" 模式 —— SPKI 里紧跟公钥 BITSTRING 的起点
    NSUInteger idx = 0;
    while (idx + 3 < len) {
        if (p[idx] == 0x03 && (p[idx+1] == 0x81 || p[idx+1] == 0x82)) {
            NSUInteger lenBytes = (p[idx+1] == 0x81) ? 1 : 2;
            NSUInteger start    = idx + 2 + lenBytes + 1; // +1 跳过 leading 0x00
            NSData *pkcs1 = [der subdataWithRange:NSMakeRange(start, len - start)];
            NSDictionary *attrs = @{
                (id)kSecAttrKeyType:       (id)kSecAttrKeyTypeRSA,
                (id)kSecAttrKeyClass:      (id)kSecAttrKeyClassPublic,
                (id)kSecAttrKeySizeInBits: @2048,
            };
            CFErrorRef err = NULL;
            SecKeyRef k = SecKeyCreateWithData((__bridge CFDataRef)pkcs1, (__bridge CFDictionaryRef)attrs, &err);
            if (err) { CFRelease(err); }
            return k;
        }
        idx++;
    }
    return NULL;
}

+ (BOOL)verifyRSA:(NSData *)message signature:(NSData *)sig publicPEM:(NSString *)pem {
    if (!message || !sig || pem.length == 0) return NO;
    SecKeyRef key = [self _createSecKeyWithPEM:pem];
    if (!key) return NO;

    BOOL ok = NO;
    if (@available(iOS 10.0, *)) {
        CFErrorRef err = NULL;
        ok = SecKeyVerifySignature(key,
                                   kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                                   (__bridge CFDataRef)message,
                                   (__bridge CFDataRef)sig,
                                   &err) == true;
        if (err) CFRelease(err);
    } else {
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(message.bytes, (CC_LONG)message.length, hash);
        OSStatus s = SecKeyRawVerify(key, kSecPaddingPKCS1SHA256,
                                     hash, sizeof(hash),
                                     sig.bytes, sig.length);
        ok = (s == errSecSuccess);
    }
    CFRelease(key);
    return ok;
}

@end
