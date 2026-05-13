//
//  PCAuthManager.m
//  PersonalCenterUI
//

#import "PCAuthManager.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#include <sys/sysctl.h>

// ====================== ★ 必改配置区 ★ ======================
static NSString *const kPCAuthServerBase = @"http://45.207.216.109:5845";
static NSString *const kPCAuthAppID      = @"pcui_default";

// 把安装向导生成的 public.pem 内容（包括 -----BEGIN PUBLIC KEY----- 行）整段粘贴到这里
static NSString *const kPCAuthPubKeyPEM = @""
"-----BEGIN PUBLIC KEY-----\n"
"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxIrSuXw2c9QyWSRI+/5L\n"
"TMIrdKxNM6LScmV6JZDxSczyV9S5fE7dcs1kD5NTUWYd9GZSIK40VJdQlM6s2HEo\n"
"MdGFoTtQ53Mt24Ytk73Q7eBU0WratHZtU8ySp959jgBEDbm3PgFLc6MEsp0e1mM0\n"
"gbBok8eGrgKGHFTHPvHWYvZvIchNpVAYV8E12KAwIhQ6ko/un5JFK0DCEFbOcBJS\n"
"35b1xKL7ZFAQ9tnWbgesN+xPQ8n/3UP4AtbaiUWioYmNhJJFxFBa03rJSjRjTQOL\n"
"LcDhQi/Ar0pxW/jpWFUYugK3KT18BoV6q3+ggPJNYozhKWKzpABF77ryjDuWn0DI\n"
"HwIDAQAB\n"
"-----END PUBLIC KEY-----\n";
// ============================================================

static NSString *const kKC_Service   = @"com.personalcenterui.auth";
static NSString *const kKC_DevAcc    = @"device_id";
static NSString *const kKC_CardAcc   = @"card_key";
static NSString *const kKC_ExpAcc    = @"expires_at";
static NSString *const kKC_SigAcc    = @"last_sig";

#pragma mark - Keychain Helpers

static NSData *PCKC_Read(NSString *account) {
    NSDictionary *q = @{
        (__bridge id)kSecClass           : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService     : kKC_Service,
        (__bridge id)kSecAttrAccount     : account,
        (__bridge id)kSecReturnData      : @YES,
        (__bridge id)kSecMatchLimit      : (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef out = NULL;
    OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (s == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        return d;
    }
    if (out) CFRelease(out);
    return nil;
}

static void PCKC_Write(NSString *account, NSData *data) {
    NSDictionary *q = @{
        (__bridge id)kSecClass       : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : kKC_Service,
        (__bridge id)kSecAttrAccount : account,
    };
    SecItemDelete((__bridge CFDictionaryRef)q);
    NSMutableDictionary *add = [q mutableCopy];
    add[(__bridge id)kSecValueData] = data ?: [NSData data];
    SecItemAdd((__bridge CFDictionaryRef)add, NULL);
}

static void PCKC_Delete(NSString *account) {
    NSDictionary *q = @{
        (__bridge id)kSecClass       : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : kKC_Service,
        (__bridge id)kSecAttrAccount : account,
    };
    SecItemDelete((__bridge CFDictionaryRef)q);
}

#pragma mark - Hash / Base64

static NSString *PCSha256Hex(NSString *input) {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char h[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, h);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", h[i]];
    return s;
}

static NSData *PCSha256Raw(NSData *data) __attribute__((unused));
static NSData *PCSha256Raw(NSData *data) {
    unsigned char h[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, h);
    return [NSData dataWithBytes:h length:CC_SHA256_DIGEST_LENGTH];
}

static NSData *PCBase64Decode(NSString *s) {
    if (!s.length) return nil;
    NSString *t = [s stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@" "  withString:@""];
    return [[NSData alloc] initWithBase64EncodedString:t options:0];
}

#pragma mark - RSA Public Key Import

/// 从 PEM（SubjectPublicKeyInfo / PKCS#1）字符串导入公钥，返回 SecKeyRef（需 release）
static SecKeyRef PCImportPubKey(NSString *pem) CF_RETURNS_RETAINED {
    if (!pem.length) return NULL;
    NSMutableString *s = [pem mutableCopy];
    [s replaceOccurrencesOfString:@"-----BEGIN PUBLIC KEY-----"  withString:@"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"-----END PUBLIC KEY-----"    withString:@"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"-----BEGIN RSA PUBLIC KEY-----" withString:@"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"-----END RSA PUBLIC KEY-----"   withString:@"" options:0 range:NSMakeRange(0, s.length)];
    NSData *der = PCBase64Decode(s);
    if (!der.length) return NULL;

    // 若是 X.509 SPKI（标准 PEM BEGIN PUBLIC KEY），跳过前 24 字节 AlgorithmIdentifier
    // 注意：iOS SecKeyCreateWithData 只接受裸 PKCS#1 公钥（DER of RSAPublicKey）
    // 这里简单判断：长度 > 24 并以 0x30 开头，截掉 SPKI 头
    NSData *pkcs1 = der;
    if (der.length > 24) {
        const uint8_t *b = der.bytes;
        // SPKI 头一般为 30 82 xx xx 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 03 82 xx xx 00
        if (b[0] == 0x30 && b[1] == 0x82) {
            // 粗暴查找 0x03 0x82 xx xx 0x00 作为 BIT STRING 标识
            for (NSUInteger i = 0; i + 5 < der.length; i++) {
                if (b[i] == 0x03 && b[i+1] == 0x82 && b[i+4] == 0x00) {
                    pkcs1 = [der subdataWithRange:NSMakeRange(i + 5, der.length - i - 5)];
                    break;
                }
            }
        }
    }

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType       : (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass      : (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits : @2048,
    };
    CFErrorRef err = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)pkcs1,
                                         (__bridge CFDictionaryRef)attrs,
                                         &err);
    if (!key) {
        // 兜底：尝试直接当 SPKI 传
        if (err) CFRelease(err);
        err = NULL;
        key = SecKeyCreateWithData((__bridge CFDataRef)der,
                                   (__bridge CFDictionaryRef)attrs,
                                   &err);
    }
    if (err) CFRelease(err);
    return key;
}

/// 使用公钥验证 RSA-SHA256 签名
static BOOL PCRSAVerify(NSString *pem, NSString *message, NSString *signB64) {
    if (!pem.length || !message.length || !signB64.length) return NO;
    SecKeyRef pub = PCImportPubKey(pem);
    if (!pub) return NO;

    NSData *msg  = [message dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sig  = PCBase64Decode(signB64);
    if (!sig.length) { CFRelease(pub); return NO; }

    CFErrorRef err = NULL;
    BOOL ok = SecKeyVerifySignature(pub,
                                    kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                                    (__bridge CFDataRef)msg,
                                    (__bridge CFDataRef)sig,
                                    &err);
    if (err) CFRelease(err);
    CFRelease(pub);
    return ok;
}

#pragma mark - Device Fingerprint

static NSString *PCHwModel(void) {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *m = (char *)malloc(size + 1);
    if (!m) return @"";
    sysctlbyname("hw.machine", m, &size, NULL, 0);
    m[size] = '\0';
    NSString *s = [NSString stringWithUTF8String:m];
    free(m);
    return s ?: @"";
}

#pragma mark - Manager

@interface PCAuthManager ()
@property (nonatomic, copy) NSString *cachedDeviceID;
@property (nonatomic, strong) dispatch_source_t hbTimer;
@property (nonatomic, copy)   void (^hbKick)(NSString *);
@end

@implementation PCAuthManager

+ (instancetype)sharedManager {
    static PCAuthManager *g; static dispatch_once_t t;
    dispatch_once(&t, ^{ g = [[PCAuthManager alloc] init]; });
    return g;
}

- (NSString *)deviceID {
    if (self.cachedDeviceID.length) return self.cachedDeviceID;

    // 优先 Keychain（重装 App 也不丢）
    NSData *d = PCKC_Read(kKC_DevAcc);
    if (d.length) {
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (s.length == 64) { self.cachedDeviceID = s; return s; }
    }

    NSString *idfv  = [UIDevice currentDevice].identifierForVendor.UUIDString ?: @"";
    NSString *name  = [UIDevice currentDevice].name ?: @"";
    NSString *model = PCHwModel();
    NSString *bundle= [NSBundle mainBundle].bundleIdentifier ?: @"";
    NSString *raw   = [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
                       kPCAuthAppID, idfv, model, name, bundle];
    NSString *hash  = PCSha256Hex(raw);
    PCKC_Write(kKC_DevAcc, [hash dataUsingEncoding:NSUTF8StringEncoding]);
    self.cachedDeviceID = hash;
    return hash;
}

- (NSString *)cachedCardKey {
    NSData *d = PCKC_Read(kKC_CardAcc);
    if (!d.length) return nil;
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

- (NSTimeInterval)cachedExpiresAt {
    NSData *d = PCKC_Read(kKC_ExpAcc);
    if (!d.length) return 0;
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return s.doubleValue;
}

- (BOOL)isLocallyAuthorized {
    NSString *card = [self cachedCardKey];
    NSTimeInterval exp = [self cachedExpiresAt];
    if (!card.length || exp <= 0) return NO;
    if ([[NSDate date] timeIntervalSince1970] >= exp) return NO;
    // 额外：校验上次服务器签名仍对得上（防止本地被改写）
    NSData *sigD = PCKC_Read(kKC_SigAcc);
    NSString *sig = sigD.length ? [[NSString alloc] initWithData:sigD encoding:NSUTF8StringEncoding] : nil;
    if (!sig.length) return NO;
    NSString *msg = [NSString stringWithFormat:@"%@|%@|%@|%.0f",
                     kPCAuthAppID, [self deviceID], card, exp];
    return PCRSAVerify(kPCAuthPubKeyPEM, msg, sig);
}

- (void)clearCache {
    PCKC_Delete(kKC_CardAcc);
    PCKC_Delete(kKC_ExpAcc);
    PCKC_Delete(kKC_SigAcc);
}

#pragma mark - Network

- (NSString *)_nonce {
    unsigned char b[16]; arc4random_buf(b, sizeof(b));
    NSMutableString *s = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 16; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

- (void)_postAction:(NSString *)action
               card:(NSString *)card
         completion:(PCAuthCompletion)completion {
    NSString *did   = [self deviceID];
    NSString *nonce = [self _nonce];
    NSTimeInterval ts = [[NSDate date] timeIntervalSince1970];

    NSDictionary *body = @{
        @"app_id"    : kPCAuthAppID,
        @"action"    : action,
        @"card"      : card ?: @"",
        @"device_id" : did,
        @"device_info": @{
            @"model" : PCHwModel(),
            @"sys"   : ([UIDevice currentDevice].systemVersion ?: @""),
            @"name"  : ([UIDevice currentDevice].name ?: @""),
            @"bundle": ([NSBundle mainBundle].bundleIdentifier ?: @""),
        },
        @"ts"        : @((long long)ts),
        @"nonce"     : nonce,
    };
    NSError *je = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&je];
    if (!data) {
        if (completion) completion(PCAuthStatusNetwork, 0, je.localizedDescription);
        return;
    }

    NSString *url = [NSString stringWithFormat:@"%@/api.php", kPCAuthServerBase];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 15;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = data;

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *sess = [NSURLSession sessionWithConfiguration:cfg];
    __weak typeof(self) ws = self;

    NSURLSessionDataTask *task = [sess dataTaskWithRequest:req
        completionHandler:^(NSData * _Nullable rd, NSURLResponse * _Nullable resp, NSError * _Nullable err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !rd.length) {
                if (completion) completion(PCAuthStatusNetwork, 0, err.localizedDescription ?: @"网络异常");
                return;
            }
            NSError *pe = nil;
            id j = [NSJSONSerialization JSONObjectWithData:rd options:0 error:&pe];
            if (![j isKindOfClass:[NSDictionary class]]) {
                if (completion) completion(PCAuthStatusNetwork, 0, @"响应解析失败");
                return;
            }
            NSDictionary *r = (NSDictionary *)j;
            NSInteger code = [r[@"code"] integerValue];
            NSString *msg  = r[@"msg"];
            NSDictionary *d = [r[@"data"] isKindOfClass:[NSDictionary class]] ? r[@"data"] : @{};
            NSTimeInterval expires = [d[@"expires_at"] doubleValue];
            NSString *sig  = d[@"sign"];

            if (code == 0) {
                // 必须通过签名校验：msg = app_id|device_id|card|expires_at
                NSString *verifyMsg = [NSString stringWithFormat:@"%@|%@|%@|%.0f",
                                       kPCAuthAppID, [ws deviceID], card ?: @"", expires];
                BOOL ok = PCRSAVerify(kPCAuthPubKeyPEM, verifyMsg, sig);
                if (!ok) {
                    if (completion) completion(PCAuthStatusSignatureBad, 0, @"签名校验失败");
                    return;
                }
                // 写缓存
                PCKC_Write(kKC_CardAcc, [(card ?: @"") dataUsingEncoding:NSUTF8StringEncoding]);
                PCKC_Write(kKC_ExpAcc, [[NSString stringWithFormat:@"%.0f", expires] dataUsingEncoding:NSUTF8StringEncoding]);
                PCKC_Write(kKC_SigAcc, [(sig ?: @"") dataUsingEncoding:NSUTF8StringEncoding]);
                if (completion) completion(PCAuthStatusValid, expires, msg);
                return;
            }
            // 非 0 错误码映射
            PCAuthStatus st = PCAuthStatusInvalid;
            switch (code) {
                case 1001: st = PCAuthStatusInvalid;        break; // 卡密不存在
                case 1002: st = PCAuthStatusInvalid;        break; // 已禁用
                case 1003: st = PCAuthStatusExpired;        break; // 已过期
                case 1004: st = PCAuthStatusDeviceMismatch; break; // 绑定不一致
                case 1005: st = PCAuthStatusNotActivated;   break;
                default:   st = PCAuthStatusInvalid;        break;
            }
            if (completion) completion(st, expires, msg ?: @"授权失败");
        });
    }];
    [task resume];
}

- (void)activateWithCard:(NSString *)card
              completion:(PCAuthCompletion)completion {
    if (!card.length) {
        if (completion) completion(PCAuthStatusInvalid, 0, @"卡密不能为空");
        return;
    }
    [self _postAction:@"activate" card:card completion:completion];
}

- (void)verifyWithCompletion:(PCAuthCompletion)completion {
    NSString *c = [self cachedCardKey];
    if (!c.length) {
        if (completion) completion(PCAuthStatusNotActivated, 0, @"未激活");
        return;
    }
    [self _postAction:@"verify" card:c completion:completion];
}

#pragma mark - Heartbeat

- (void)startHeartbeatWithInterval:(NSTimeInterval)seconds
                         onKicked:(void(^)(NSString * _Nullable))onKicked {
    [self stopHeartbeat];
    self.hbKick = onKicked;
    if (seconds < 30) seconds = 300; // 最小 30s，默认 5min
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                 0, 0, dispatch_get_main_queue());
    uint64_t iv = (uint64_t)(seconds * NSEC_PER_SEC);
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, iv), iv, (uint64_t)(10 * NSEC_PER_SEC));
    __weak typeof(self) ws = self;
    dispatch_source_set_event_handler(t, ^{
        __strong typeof(ws) ss = ws; if (!ss) return;
        // 先做本地到期检查
        NSTimeInterval exp = [ss cachedExpiresAt];
        if (exp > 0 && [[NSDate date] timeIntervalSince1970] >= exp) {
            if (ss.hbKick) ss.hbKick(@"授权已到期");
            return;
        }
        // 服务器验证
        [ss verifyWithCompletion:^(PCAuthStatus status, NSTimeInterval expiresAt, NSString * _Nullable message) {
            if (status == PCAuthStatusExpired || status == PCAuthStatusInvalid
                || status == PCAuthStatusDeviceMismatch
                || status == PCAuthStatusSignatureBad
                || status == PCAuthStatusNotActivated) {
                [ss clearCache];
                if (ss.hbKick) ss.hbKick(message ?: @"授权失效");
            }
            // 网络异常不踢人
        }];
    });
    self.hbTimer = t;
    dispatch_resume(t);
}

- (void)stopHeartbeat {
    if (self.hbTimer) {
        dispatch_source_cancel(self.hbTimer);
        self.hbTimer = nil;
    }
    self.hbKick = nil;
}

@end
