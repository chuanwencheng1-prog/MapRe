//
//  PCAuthManager.m
//  PersonalCenterUI
//

#import "PCAuthManager.h"
#import "PCAuthCrypto.h"
#import "PCAntiCrack.h"
#import "PCPakDownloader.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

// 本地缓存文件：放 /var/mobile/Library/Preferences/.pcui_auth.dat
static NSString *PCAuthCachePath(void) {
    NSString *dir = @"/var/mobile/Library/Preferences";
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        dir = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
    }
    return [dir stringByAppendingPathComponent:@".pcui_auth.dat"];
}

static NSString *PCDeviceModel(void) {
    struct utsname u; uname(&u);
    return [NSString stringWithUTF8String:u.machine] ?: @"unknown";
}

@interface PCAuthManager ()
@property (nonatomic, copy)   NSString *fingerprint;       // 设备指纹
@property (nonatomic, copy)   NSString *sessionKey;        // 服务器下发
@property (nonatomic, assign) NSTimeInterval sessionExpireAt;
@property (nonatomic, assign) NSTimeInterval boundUntilTs;
@property (nonatomic, assign) NSInteger level;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) dispatch_queue_t q;
@end

@implementation PCAuthManager

+ (instancetype)sharedManager {
    static PCAuthManager *m = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [[self alloc] init]; });
    return m;
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = dispatch_queue_create("com.pcui.auth.q", DISPATCH_QUEUE_SERIAL);
        _fingerprint = [self _computeFingerprint];
        [self _loadCache];
    }
    return self;
}

#pragma mark - Public

- (NSString *)deviceFingerprint { return _fingerprint ?: @""; }
- (NSDate *)boundUntil {
    return _boundUntilTs > 0 ? [NSDate dateWithTimeIntervalSince1970:_boundUntilTs] : nil;
}

- (BOOL)isActivated {
    // 多重校验：任何一项不满足都视为未激活
    if (_fingerprint.length == 0)                    return NO;
    if (_sessionKey.length   == 0)                   return NO;
    if (_boundUntilTs <= 0)                          return NO;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (_boundUntilTs   < now)                       return NO;
    if (_sessionExpireAt < now - 60)                 return NO; // 会话过期也视为失效
    return YES;
}

- (void)signOut {
    dispatch_sync(_q, ^{
        self.sessionKey      = @"";
        self.sessionExpireAt = 0;
        self.boundUntilTs    = 0;
        self.level           = 0;
        [[NSFileManager defaultManager] removeItemAtPath:PCAuthCachePath() error:nil];
    });
    [self _stopHeartbeat];
}

- (void)bootstrapWithCompletion:(PCAuthCompletion)completion {
    NSString *reason = nil;
    if (![PCAntiCrack check:&reason]) {
        if (completion) completion(NO, [NSString stringWithFormat:@"环境异常：%@", reason ?: @"unknown"]);
        return;
    }
    if (![self isActivated]) {
        if (completion) completion(NO, @"未激活，请输入激活码");
        return;
    }
    // 有本地态 → 尝试心跳
    [self _request:@"heartbeat" payload:@{@"ver": [self _clientVer]} completion:^(BOOL ok, NSDictionary *resp, NSString *msg) {
        if (ok) {
            [self _startHeartbeat];
            if (completion) completion(YES, @"已激活");
        } else {
            // 心跳失败视为掉线，要求用户重新激活
            [self signOut];
            if (completion) completion(NO, msg ?: @"会话失效，请重新激活");
        }
    }];
}

- (void)activateWithCode:(NSString *)code completion:(PCAuthCompletion)completion {
    NSString *reason = nil;
    if (![PCAntiCrack check:&reason]) {
        if (completion) completion(NO, [NSString stringWithFormat:@"环境异常：%@", reason ?: @"unknown"]);
        return;
    }
    code = [[code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if (code.length < 8) { if (completion) completion(NO, @"激活码格式不正确"); return; }

    NSDictionary *payload = @{
        @"code":   code,
        @"model":  PCDeviceModel(),
        @"system": [[UIDevice currentDevice] systemVersion] ?: @"",
        @"bundle": [[NSBundle mainBundle] bundleIdentifier] ?: @"",
        @"ver":    [self _clientVer],
    };
    [self _request:@"activate" payload:payload completion:^(BOOL ok, NSDictionary *resp, NSString *msg) {
        if (!ok) { if (completion) completion(NO, msg); return; }
        self.sessionKey      = [resp[@"session_key"] description] ?: @"";
        self.sessionExpireAt = [resp[@"session_expires_at"] doubleValue];
        self.boundUntilTs    = [resp[@"bound_until"]        doubleValue];
        self.level           = [resp[@"level"]              integerValue];
        [self _saveCache];
        [self _startHeartbeat];
        if (completion) completion(YES, [resp[@"msg"] description] ?: @"激活成功");
    }];
}

- (void)heartbeat {
    if (![self isActivated]) {
        // 本地已过期，触发清理+闪退
        [self expireAndCleanup];
        return;
    }
    [self _request:@"heartbeat" payload:@{@"ver": [self _clientVer]} completion:^(BOOL ok, NSDictionary *r, NSString *msg) {
        if (!ok) {
            [self signOut];
            // 心跳失败（服务端踢下线/到期），执行清理+闪退
            [self expireAndCleanup];
        }
        else {
            self.boundUntilTs    = [r[@"bound_until"]        doubleValue] ?: self.boundUntilTs;
            self.sessionExpireAt = [r[@"session_expires_at"] doubleValue] ?: self.sessionExpireAt;
            [self _saveCache];
            // 心跳成功后再检查一次是否已到期
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if (self.boundUntilTs > 0 && self.boundUntilTs < now) {
                [self expireAndCleanup];
            }
        }
    }];
}

#pragma mark - 到期清理 + 闪退

- (void)expireAndCleanup {
    NSLog(@"[PersonalCenterUI] 卡密到期，开始清理 pak 文件...");

    // 清理目标 App 沙箱中已下载的 pak 文件
    [self _cleanDownloadedPakFiles];

    // 清除本地缓存
    [self signOut];

    // 延迟 0.5 秒后闪退（确保文件删除完成）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[PersonalCenterUI] 清理完成，执行闪退");
        // 使用未公开的 exit 强制结束进程
        exit(0);
    });
}

/// 仅清理本工具下载过的 pak 文件（通过下载记录定位，不会删除目录下其它 pak）
- (void)_cleanDownloadedPakFiles {
    NSArray<NSString *> *downloadedPaths = [PCPakDownloader downloadedFilePaths];
    if (downloadedPaths.count == 0) {
        NSLog(@"[PersonalCenterUI] 清理：无已下载记录，跳过");
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in downloadedPaths) {
        if ([fm fileExistsAtPath:path]) {
            NSError *rmErr = nil;
            [fm removeItemAtPath:path error:&rmErr];
            if (rmErr) {
                NSLog(@"[PersonalCenterUI] 删除失败：%@ - %@", path.lastPathComponent, rmErr.localizedDescription);
            } else {
                NSLog(@"[PersonalCenterUI] 已删除：%@", path.lastPathComponent);
            }
        } else {
            NSLog(@"[PersonalCenterUI] 文件不存在，跳过：%@", path.lastPathComponent);
        }
    }

    // 清除下载记录
    [PCPakDownloader clearDownloadedFilesRecord];
}

#pragma mark - 指纹

- (NSString *)_computeFingerprint {
    NSString *idfv   = [[UIDevice currentDevice].identifierForVendor UUIDString] ?: @"";
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *model  = PCDeviceModel();
    NSString *os     = [[UIDevice currentDevice].systemVersion componentsSeparatedByString:@"."].firstObject ?: @"";
    // 混入一个编译期 salt（与服务端无关，仅稳定性用）
    NSString *composite = [NSString stringWithFormat:@"%@|%@|%@|%@|pcui", idfv, bundle, model, os];
    NSData *h = [PCAuthCrypto sha256:[composite dataUsingEncoding:NSUTF8StringEncoding]];
    return [PCAuthCrypto hexString:h];
}

- (NSString *)_clientVer { return @"1.0.0"; }

#pragma mark - 心跳

- (void)_startHeartbeat {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _stopHeartbeat];
        self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:300
                                                               target:self
                                                             selector:@selector(heartbeat)
                                                             userInfo:nil
                                                              repeats:YES];
    });
}

- (void)_stopHeartbeat {
    [_heartbeatTimer invalidate];
    _heartbeatTimer = nil;
}

#pragma mark - 本地缓存（AES 加密，设备指纹派生密钥）

- (NSString *)_cacheKeyMaterial {
    // 设备指纹 + 编译期常量混合，离开本机无法解密
    return [NSString stringWithFormat:@"pcui-auth-v1::%@", self.fingerprint];
}

- (void)_loadCache {
    NSData *raw = [NSData dataWithContentsOfFile:PCAuthCachePath()];
    if (raw.length < 16 + 32) return;

    NSData *iv  = [raw subdataWithRange:NSMakeRange(0, 16)];
    NSData *tag = [raw subdataWithRange:NSMakeRange(16, 32)];
    NSData *ct  = [raw subdataWithRange:NSMakeRange(48, raw.length - 48)];

    // HMAC 自校验：tag = HMAC(iv||ct, km)
    NSMutableData *msg = [NSMutableData dataWithData:iv]; [msg appendData:ct];
    NSData *km  = [[self _cacheKeyMaterial] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *mac = [PCAuthCrypto hmacSHA256:msg key:km];
    if (![mac isEqualToData:tag]) return;

    NSData *pt = [PCAuthCrypto aesDecrypt:ct keyMaterial:[self _cacheKeyMaterial] iv:iv];
    if (!pt) return;
    NSDictionary *d = [NSJSONSerialization JSONObjectWithData:pt options:0 error:nil];
    if (![d isKindOfClass:[NSDictionary class]]) return;

    // 指纹复核
    if (![[d objectForKey:@"fp"] isEqualToString:self.fingerprint]) return;
    self.sessionKey      = [d[@"sk"] description] ?: @"";
    self.sessionExpireAt = [d[@"se"] doubleValue];
    self.boundUntilTs    = [d[@"bu"] doubleValue];
    self.level           = [d[@"lv"] integerValue];
}

- (void)_saveCache {
    NSDictionary *d = @{
        @"fp": self.fingerprint ?: @"",
        @"sk": self.sessionKey   ?: @"",
        @"se": @(self.sessionExpireAt),
        @"bu": @(self.boundUntilTs),
        @"lv": @(self.level),
    };
    NSData *pt = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    if (!pt) return;
    NSData *iv = [PCAuthCrypto randomBytes:16];
    NSData *ct = [PCAuthCrypto aesEncrypt:pt keyMaterial:[self _cacheKeyMaterial] iv:iv];
    if (!ct) return;

    NSMutableData *msg = [NSMutableData dataWithData:iv]; [msg appendData:ct];
    NSData *km  = [[self _cacheKeyMaterial] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *tag = [PCAuthCrypto hmacSHA256:msg key:km];

    NSMutableData *out = [NSMutableData data];
    [out appendData:iv]; [out appendData:tag]; [out appendData:ct];
    [out writeToFile:PCAuthCachePath() atomically:YES];
}

#pragma mark - 网络层

- (void)_request:(NSString *)act payload:(NSDictionary *)payload completion:(void(^)(BOOL ok, NSDictionary *resp, NSString *msg))completion {
    dispatch_async(_q, ^{
        NSURL *url = [NSURL URLWithString:[PCAuthCrypto apiURL]];
        if (!url) { if (completion) completion(NO, nil, @"API 地址未配置"); return; }

        // shared key 判定
        NSString *shared = [act isEqualToString:@"activate"] ? [PCAuthCrypto baseSecret] : (self.sessionKey ?: @"");
        if (shared.length == 0) { if (completion) completion(NO, nil, @"会话密钥缺失"); return; }

        // 加密 payload
        NSData *pt = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        NSData *iv = [PCAuthCrypto randomBytes:16];
        NSData *ct = [PCAuthCrypto aesEncrypt:pt keyMaterial:shared iv:iv];
        if (!ct) { if (completion) completion(NO, nil, @"加密失败"); return; }
        NSString *bodyB = [PCAuthCrypto b64uEncode:ct];
        NSString *ivB   = [PCAuthCrypto b64uEncode:iv];

        long long ts = (long long)[[NSDate date] timeIntervalSince1970];
        NSString *nonce = [PCAuthCrypto hexString:[PCAuthCrypto randomBytes:16]];
        NSString *fp    = self.fingerprint ?: @"";
        int ver         = 1;

        NSString *canonical = [NSString stringWithFormat:@"%d|%@|%lld|%@|%@|%@|%@",
                               ver, act, ts, nonce, fp, bodyB, ivB];
        NSData *sig = [PCAuthCrypto hmacSHA256:[canonical dataUsingEncoding:NSUTF8StringEncoding]
                                           key:[shared dataUsingEncoding:NSUTF8StringEncoding]];

        NSDictionary *req = @{
            @"v":     @(ver),
            @"act":   act,
            @"ts":    @(ts),
            @"nonce": nonce,
            @"fp":    fp,
            @"body":  bodyB,
            @"iv":    ivB,
            @"sig":   [PCAuthCrypto hexString:sig],
        };
        NSData *reqData = [NSJSONSerialization dataWithJSONObject:req options:0 error:nil];

        NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
        r.HTTPMethod = @"POST";
        r.timeoutInterval = 15.0;
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [r setValue:@"PCUIAuth/1.0"     forHTTPHeaderField:@"User-Agent"];
        r.HTTPBody = reqData;

        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.TLSMinimumSupportedProtocolVersion = tls_protocol_version_TLSv12;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
        [[session dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
            if (err) { if (completion) completion(NO, nil, err.localizedDescription); return; }
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if (![j isKindOfClass:[NSDictionary class]]) { if (completion) completion(NO, nil, @"响应解析失败"); return; }
            if (![j[@"ok"] boolValue]) {
                NSString *m = [j[@"msg"] description] ?: @"验证失败";
                if (completion) completion(NO, nil, m);
                return;
            }
            NSString *bodyRespB = [j[@"body"] description];
            NSString *ivRespB   = [j[@"iv"]   description];
            NSString *sigRespB  = [j[@"sig"]  description];
            if (bodyRespB.length == 0 || ivRespB.length == 0) {
                if (completion) completion(NO, nil, @"响应字段缺失"); return;
            }
            // RSA 验签（公钥在本地，服务器无法伪造签名 → 强防 MITM）
            NSString *toSign = [NSString stringWithFormat:@"%@|%@", bodyRespB, ivRespB];
            NSData *hash    = [PCAuthCrypto sha256:[toSign dataUsingEncoding:NSUTF8StringEncoding]];
            NSData *sigData = [PCAuthCrypto b64uDecode:sigRespB];
            NSString *pem   = [PCAuthCrypto rsaPublicPEM];
            BOOL sigOk = YES;
            if (pem.length > 0 && ![pem containsString:@"PASTE_YOUR_PUBLIC_KEY"]) {
                sigOk = [PCAuthCrypto verifyRSA:hash signature:sigData publicPEM:pem];
            }
            if (!sigOk) { if (completion) completion(NO, nil, @"响应签名校验失败"); return; }

            // 解密
            NSData *ctR = [PCAuthCrypto b64uDecode:bodyRespB];
            NSData *ivR = [PCAuthCrypto b64uDecode:ivRespB];
            NSData *pt  = [PCAuthCrypto aesDecrypt:ctR keyMaterial:shared iv:ivR];
            if (!pt) { if (completion) completion(NO, nil, @"响应解密失败"); return; }
            NSDictionary *inner = [NSJSONSerialization JSONObjectWithData:pt options:0 error:nil];
            if (![inner isKindOfClass:[NSDictionary class]]) { if (completion) completion(NO, nil, @"响应解析失败"); return; }
            if (completion) completion(YES, inner, [inner[@"msg"] description] ?: @"ok");
        }] resume];
    });
}

@end
