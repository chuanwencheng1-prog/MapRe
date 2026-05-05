//
//  PCAuthManager.m
//  PersonalCenterUI
//

#import "PCAuthManager.h"
#import "PCAuthCrypto.h"
#import "PCAntiCrack.h"
#import "PCDeviceID.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

NSString *const PCAuthStatusDidChangeNotification = @"PCAuthStatusDidChangeNotification";

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

// 连续心跳失败达到该值后，服务器视为离线 —— 触发 UI 清空所有直链布局
static const NSInteger kPCServerOfflineThreshold = 3;

@interface PCAuthManager ()
@property (nonatomic, copy)   NSString *fingerprint;       // 现在 == UDID
@property (nonatomic, copy)   NSString *sessionKey;        // 服务器下发
@property (nonatomic, assign) NSTimeInterval sessionExpireAt;
@property (nonatomic, assign) NSTimeInterval boundUntilTs;
@property (nonatomic, assign) NSInteger level;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) dispatch_queue_t q;

// 服务器在线状态
@property (atomic, assign)    BOOL      serverOnline;
@property (atomic, assign)    NSInteger consecutiveFailures;
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
        _fingerprint = [[PCDeviceID udid] copy];    // ← 直接使用真 UDID
        _serverOnline = NO;                         // 首次启动保守：未探测前视为离线
        _consecutiveFailures = 0;
        [self _loadCache];
    }
    return self;
}

#pragma mark - Public

- (NSString *)deviceFingerprint { return _fingerprint ?: @""; }
- (NSString *)deviceUDID        { return [PCDeviceID udid]; }
- (NSString *)udidSource        { return [PCDeviceID source]; }

- (NSDate *)boundUntil {
    return _boundUntilTs > 0 ? [NSDate dateWithTimeIntervalSince1970:_boundUntilTs] : nil;
}

- (BOOL)isServerOnline { return _serverOnline; }

- (BOOL)isActivated {
    // 多重校验：任何一项不满足都视为未激活
    if (_fingerprint.length == 0)                    return NO;
    if (_sessionKey.length   == 0)                   return NO;
    if (_boundUntilTs < 0)                           return NO;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    // boundUntilTs == 0 表示"永久"（服务端 duration_seconds = -1 下发），不做过期判断
    if (_boundUntilTs > 0 && _boundUntilTs < now)    return NO;
    if (_sessionExpireAt > 0 && _sessionExpireAt < now - 60) return NO; // 会话过期也视为失效
    return YES;
}

- (void)signOut {
    [self _signOutWithReason:@"kicked"];
}

- (void)_signOutWithReason:(NSString *)reason {
    dispatch_sync(_q, ^{
        self.sessionKey      = @"";
        self.sessionExpireAt = 0;
        self.boundUntilTs    = 0;
        self.level           = 0;
        [[NSFileManager defaultManager] removeItemAtPath:PCAuthCachePath() error:nil];
    });
    [self _stopHeartbeat];
    [self _postStatusChange:reason ?: @"kicked"];
}

- (void)_postStatusChange:(NSString *)reason {
    NSDictionary *info = @{
        @"activated": @([self isActivated]),
        @"online":    @(self.serverOnline),
        @"reason":    reason ?: @"",
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:PCAuthStatusDidChangeNotification
                          object:self
                        userInfo:info];
    });
}

- (void)_setServerOnline:(BOOL)online {
    if (self.serverOnline == online) return;
    self.serverOnline = online;
    [self _postStatusChange:online ? @"online" : @"offline"];
}

#pragma mark - bootstrap / activate / heartbeat

- (void)bootstrapWithCompletion:(PCAuthCompletion)completion {
    // 环境检测：抓包/VPN/调试/注入 → 直接闪退，不再继续
    [PCAntiCrack crashIfEnvCompromised:NULL];

    // 先走一次 ping 探活（无需 session，用 base_secret）。
    //   · 成功 → serverOnline = YES
    //   · 失败 → serverOnline = NO（UI 将隐藏所有直链布局）
    [self _pingWithCompletion:^(BOOL pingOk) {
        [self _setServerOnline:pingOk];

        if (!pingOk) {
            // 服务器关闭：界面保持空白，无需本地激活态
            if (completion) completion(NO, @"服务器暂不可用");
            return;
        }

        if (![self isActivated]) {
            if (completion) completion(NO, @"未激活，请输入激活码");
            return;
        }

        // 已激活 → 尝试心跳
        [self _request:@"heartbeat" payload:@{@"ver": [self _clientVer]} completion:^(BOOL ok, NSDictionary *resp, NSString *msg) {
            if (ok) {
                [self _startHeartbeat];
                if (completion) completion(YES, @"已激活");
            } else {
                // 心跳失败视为掉线，优雅下线（不 abort）
                [self _signOutWithReason:@"expired"];
                if (completion) completion(NO, msg ?: @"会话失效，请重新激活");
            }
        }];
    }];
}

- (void)activateWithCode:(NSString *)code completion:(PCAuthCompletion)completion {
    // 激活行为也必须在洁净环境下进行
    [PCAntiCrack crashIfEnvCompromised:NULL];

    code = [[code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if (code.length < 8) { if (completion) completion(NO, @"激活码格式不正确"); return; }

    NSDictionary *payload = @{
        @"code":   code,
        @"udid":   [PCDeviceID udid] ?: @"",                                 // ← 明确提交真 UDID
        @"src":    [PCDeviceID source] ?: @"",
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
        [self _setServerOnline:YES];
        [self _postStatusChange:@"activated"];
        if (completion) completion(YES, [resp[@"msg"] description] ?: @"激活成功");
    }];
}

- (void)heartbeat {
    if (![self isActivated]) return;
    [self _request:@"heartbeat" payload:@{@"ver": [self _clientVer]} completion:^(BOOL ok, NSDictionary *r, NSString *msg) {
        if (!ok) {
            // 到期或被踢 → signOut 发通知（不闪退）
            [self _signOutWithReason:@"expired"];
        } else {
            self.boundUntilTs    = [r[@"bound_until"]        doubleValue] ?: self.boundUntilTs;
            self.sessionExpireAt = [r[@"session_expires_at"] doubleValue] ?: self.sessionExpireAt;
            [self _saveCache];
        }
    }];
}

#pragma mark - ping 探活（不走 session，用 base_secret）

- (void)_pingWithCompletion:(void(^)(BOOL ok))cb {
    dispatch_async(_q, ^{
        NSURL *url = [NSURL URLWithString:[PCAuthCrypto apiURL]];
        if (!url) { if (cb) cb(NO); return; }

        NSString *shared = [PCAuthCrypto baseSecret];
        NSDictionary *payload = @{ @"ver": [self _clientVer] };
        NSData *pt = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        NSData *iv = [PCAuthCrypto randomBytes:16];
        NSData *ct = [PCAuthCrypto aesEncrypt:pt keyMaterial:shared iv:iv];
        if (!ct) { if (cb) cb(NO); return; }
        NSString *bodyB = [PCAuthCrypto b64uEncode:ct];
        NSString *ivB   = [PCAuthCrypto b64uEncode:iv];

        long long ts = (long long)[[NSDate date] timeIntervalSince1970];
        NSString *nonce = [PCAuthCrypto hexString:[PCAuthCrypto randomBytes:16]];
        NSString *fp    = self.fingerprint ?: @"";

        NSString *canonical = [NSString stringWithFormat:@"%d|%@|%lld|%@|%@|%@|%@",
                               1, @"ping", ts, nonce, fp, bodyB, ivB];
        NSData *sig = [PCAuthCrypto hmacSHA256:[canonical dataUsingEncoding:NSUTF8StringEncoding]
                                           key:[shared dataUsingEncoding:NSUTF8StringEncoding]];

        NSDictionary *req = @{
            @"v":     @(1),
            @"act":   @"ping",
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
        r.timeoutInterval = 8.0;
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [r setValue:@"PCUIAuth/1.0"     forHTTPHeaderField:@"User-Agent"];
        r.HTTPBody = reqData;

        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.TLSMinimumSupportedProtocolVersion = tls_protocol_version_TLSv12;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
        [[session dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
            if (err || d.length == 0) { if (cb) cb(NO); return; }
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if (![j isKindOfClass:[NSDictionary class]]) { if (cb) cb(NO); return; }
            if (cb) cb([j[@"ok"] boolValue]);
        }] resume];
    });
}

#pragma mark - 客户端版本

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

#pragma mark - 本地缓存（AES 加密，UDID 派生密钥）

- (NSString *)_cacheKeyMaterial {
    // 真 UDID + 编译期常量混合，离开本机无法解密
    return [NSString stringWithFormat:@"pcui-auth-v2::%@", self.fingerprint ?: @""];
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

    // UDID 复核
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
    // 每次网络请求前再查一次抓包/VPN，抓到直接 abort —— 抓不到我们的直链
    [PCAntiCrack crashIfEnvCompromised:NULL];

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
            if (err) {
                // 网络层错误 → 累计失败 → 达到阈值判定服务器离线
                [self _onNetworkFailure];
                if (completion) completion(NO, nil, err.localizedDescription);
                return;
            }
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if (![j isKindOfClass:[NSDictionary class]]) {
                [self _onNetworkFailure];
                if (completion) completion(NO, nil, @"响应解析失败");
                return;
            }
            // 收到合法响应就视为"在线"
            self.consecutiveFailures = 0;
            [self _setServerOnline:YES];

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
            // RSA 验签
            NSString *toSign = [NSString stringWithFormat:@"%@|%@", bodyRespB, ivRespB];
            NSData *hash    = [PCAuthCrypto sha256:[toSign dataUsingEncoding:NSUTF8StringEncoding]];
            NSData *sigData = [PCAuthCrypto b64uDecode:sigRespB];
            NSString *pem   = [PCAuthCrypto rsaPublicPEM];
            BOOL sigOk = YES;
            if (pem.length > 0 && ![pem containsString:@"PASTE_YOUR_PUBLIC_KEY"]) {
                sigOk = [PCAuthCrypto verifyRSA:hash signature:sigData publicPEM:pem];
            }
            if (!sigOk) { if (completion) completion(NO, nil, @"响应签名校验失败"); return; }

            NSData *ctR = [PCAuthCrypto b64uDecode:bodyRespB];
            NSData *ivR = [PCAuthCrypto b64uDecode:ivRespB];
            NSData *pt2  = [PCAuthCrypto aesDecrypt:ctR keyMaterial:shared iv:ivR];
            if (!pt2) { if (completion) completion(NO, nil, @"响应解密失败"); return; }
            NSDictionary *inner = [NSJSONSerialization JSONObjectWithData:pt2 options:0 error:nil];
            if (![inner isKindOfClass:[NSDictionary class]]) { if (completion) completion(NO, nil, @"响应解析失败"); return; }
            if (completion) completion(YES, inner, [inner[@"msg"] description] ?: @"ok");
        }] resume];
    });
}

- (void)_onNetworkFailure {
    NSInteger n = self.consecutiveFailures + 1;
    self.consecutiveFailures = n;
    if (n >= kPCServerOfflineThreshold) {
        [self _setServerOnline:NO];
    }
}

@end
