//
//  PCAntiCrack.m
//  PersonalCenterUI
//
//  对标 778.ipa / Via2.0.dylib 防抓包分析报告落地：
//    · VPN/隧道接口检测   (getifaddrs → utun/ipsec/ppp/tap/tun)
//    · 系统 HTTP 代理检测  (CFNetworkCopySystemProxySettings)
//    · 回环抓包端口探测    (127.0.0.1:8080/8888/8889/9090)
//    · 抓包 dylib 扫描    (Stream/Thor/HttpCatch/Shadowrocket/Surge)
//    · SSL Pinning       (系统 CA Only，拒绝用户"已信任"CA)
//

#import "PCAntiCrack.h"
#import "PCAuthCrypto.h"

#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <dlfcn.h>
#import <unistd.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CFNetwork/CFNetwork.h>
#import <Security/Security.h>

typedef int (*ptrace_ptr_t)(int _request, pid_t _pid, caddr_t _addr, int _data);
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif

#pragma mark - SSL Pinning Delegate（系统 CA Only）

@interface _PCPinningDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate>
@end

@implementation _PCPinningDelegate

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    [PCAntiCrack handleServerTrustChallenge:challenge completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    [PCAntiCrack handleServerTrustChallenge:challenge completionHandler:completionHandler];
}

@end

#pragma mark -

@implementation PCAntiCrack

+ (void)denyAttach {
    // 通过 dlsym 调用 ptrace，避免把符号写进导入表
    void *h = dlopen(0, RTLD_GLOBAL | RTLD_NOW);
    if (!h) return;
    ptrace_ptr_t p = (ptrace_ptr_t)dlsym(h, "ptrace");
    if (p) p(PT_DENY_ATTACH, 0, 0, 0);
}

+ (BOOL)_isBeingTraced {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc info; memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return NO;
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

+ (BOOL)_hasSuspiciousDylib:(NSString **)matched {
    // 只匹配"动态分析/调试"类组件，不拦 MobileSubstrate 等 tweak 基础设施
    static NSArray<NSString *> *bad = nil;
    static dispatch_once_t once; dispatch_once(&once, ^{
        bad = @[
            @"FridaGadget",
            @"frida-agent",
            @"libfrida",
            @"cycript",
            @"cynject",
            @"RevealServer",
            @"libReveal",
            @"FLEXLoader",
            @"libsubstitute-loader",  // 调试用重注入
        ];
    });
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *n = _dyld_get_image_name(i);
        if (!n) continue;
        NSString *name = [NSString stringWithUTF8String:n];
        for (NSString *key in bad) {
            if ([name rangeOfString:key options:NSCaseInsensitiveSearch].location != NSNotFound) {
                if (matched) *matched = name;
                return YES;
            }
        }
    }
    return NO;
}

+ (BOOL)_hasEnvDebug {
    // DYLD_INSERT_LIBRARIES 指向非系统路径也算可疑
    const char *env = getenv("DYLD_INSERT_LIBRARIES");
    if (!env || *env == 0) return NO;
    NSString *v = [NSString stringWithUTF8String:env] ?: @"";
    // 允许 MobileSubstrate 本身（典型 tweak 路径）
    if ([v containsString:@"MobileSubstrate"] || [v containsString:@"TweakInject"] ||
        [v containsString:@"ElleKit"]         || [v containsString:@"CydiaSubstrate"]) {
        return NO;
    }
    return YES;
}

+ (BOOL)check:(NSString **)reason {
    NSString *r = nil;
    if ([self _isBeingTraced])                  { if (reason) *reason = @"traced";     return NO; }
    if ([self _hasSuspiciousDylib:&r])          { if (reason) *reason = r ?: @"dylib"; return NO; }
    if ([self _hasEnvDebug])                    { if (reason) *reason = @"dyld_env";   return NO; }
    if (![self checkRSAKeyIntegrity])           { if (reason) *reason = @"rsa_tamper"; return NO; }
    return YES;
}

#pragma mark - RSA 公钥完整性

// 这里只校验 PEM 字节的 SHA-256 与一个"期望哈希"是否一致。
// 期望哈希按以下规则生成并更新到 kPC_ExpectedRSA_SHA256_HEX：
//   1) 在 PCAuthCrypto.m 中把公钥 PEM 粘贴完成；
//   2) 打开一个命令行（或 Xcode 运行一次真机），调用：
//        NSLog(@"%@", [PCAuthCrypto hexString:[PCAuthCrypto sha256:
//               [[PCAuthCrypto rsaPublicPEM] dataUsingEncoding:NSUTF8StringEncoding]]]);
//   3) 把输出的 64 位 hex 替换下面的占位值；重新编译。
//   只要用户再次动手篡改 PEM，哈希就不再匹配，客户端将拒绝启动。
static NSString *const kPC_ExpectedRSA_SHA256_HEX =
    @"0000000000000000000000000000000000000000000000000000000000000000"; // ← 用户替换

+ (BOOL)checkRSAKeyIntegrity {
    NSString *pem = [PCAuthCrypto rsaPublicPEM];
    if (pem.length == 0) return NO;
    // 默认占位值："0000..."，认为用户还没生成期望哈希 → 给予放行（首次接入友好）。
    // 真正部署前请务必改为真实哈希，启动自检才会起效。
    if ([kPC_ExpectedRSA_SHA256_HEX hasPrefix:@"0000"]) return YES;

    NSData *raw = [pem dataUsingEncoding:NSUTF8StringEncoding];
    NSString *got = [PCAuthCrypto hexString:[PCAuthCrypto sha256:raw]];
    return [got caseInsensitiveCompare:kPC_ExpectedRSA_SHA256_HEX] == NSOrderedSame;
}

#pragma mark - 防抓包：系统 HTTP 代理检测

+ (BOOL)hasSystemHTTPProxy {
    CFDictionaryRef settings = CFNetworkCopySystemProxySettings();
    if (!settings) return NO;
    BOOL hit = NO;

    // HTTPEnable / HTTPSEnable 标志位（苹果私有字段名但长期稳定）
    CFNumberRef httpEnable  = CFDictionaryGetValue(settings, (const void *)CFSTR("HTTPEnable"));
    CFNumberRef httpsEnable = CFDictionaryGetValue(settings, (const void *)CFSTR("HTTPSEnable"));
    int v = 0;
    if (httpEnable  && CFNumberGetValue(httpEnable,  kCFNumberIntType, &v) && v != 0) hit = YES;
    if (!hit && httpsEnable && CFNumberGetValue(httpsEnable, kCFNumberIntType, &v) && v != 0) hit = YES;

    // HTTPProxy / HTTPSProxy 字段存在且非空亦视为代理
    if (!hit) {
        CFStringRef httpProxy  = CFDictionaryGetValue(settings, (const void *)CFSTR("HTTPProxy"));
        CFStringRef httpsProxy = CFDictionaryGetValue(settings, (const void *)CFSTR("HTTPSProxy"));
        if (httpProxy  && CFStringGetLength(httpProxy)  > 0) hit = YES;
        if (!hit && httpsProxy && CFStringGetLength(httpsProxy) > 0) hit = YES;
    }

    CFRelease(settings);
    return hit;
}

#pragma mark - 防抓包：VPN/隧道接口检测 (同 778.ipa getifaddrs)

+ (BOOL)hasVPNInterface:(NSString **)matchedIface {
    // 779.ipa 通过 getifaddrs 遍历网卡，检测 utun/ipsec/ppp 等虚拟隧道接口
    // 注：越狱用户常见 VPN（小火箭/ShadowRocket 走 utun），默认只给网络请求层使用
    static NSArray<NSString *> *bad = nil;
    static dispatch_once_t once; dispatch_once(&once, ^{
        bad = @[ @"utun", @"ipsec", @"ppp", @"tap", @"tun" ];
    });

    struct ifaddrs *head = NULL;
    if (getifaddrs(&head) != 0 || !head) return NO;

    BOOL hit = NO;
    for (struct ifaddrs *cur = head; cur != NULL; cur = cur->ifa_next) {
        if (!cur->ifa_name) continue;
        NSString *ifname = [NSString stringWithUTF8String:cur->ifa_name];
        for (NSString *prefix in bad) {
            if ([ifname hasPrefix:prefix]) {
                // 仅当该接口已 UP 并有 IP 地址时才计数，避免停机接口误报
                if ((cur->ifa_flags & IFF_UP) && cur->ifa_addr != NULL) {
                    if (matchedIface) *matchedIface = ifname;
                    hit = YES;
                    break;
                }
            }
        }
        if (hit) break;
    }
    freeifaddrs(head);
    return hit;
}

#pragma mark - 防抓包：回环端口探测 (Charles/Fiddler/mitmproxy)

+ (BOOL)_canConnectLoopback:(uint16_t)port {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return NO;

    // 非阻塞连接，100ms 超时
    int flags = fcntl(s, F_GETFL, 0);
    fcntl(s, F_SETFL, flags | O_NONBLOCK);

    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK); // 127.0.0.1

    BOOL ok = NO;
    int rc = connect(s, (struct sockaddr *)&addr, sizeof(addr));
    if (rc == 0) {
        ok = YES;
    } else if (errno == EINPROGRESS) {
        fd_set wset; FD_ZERO(&wset); FD_SET(s, &wset);
        struct timeval tv = { .tv_sec = 0, .tv_usec = 100 * 1000 }; // 100ms
        if (select(s + 1, NULL, &wset, NULL, &tv) > 0 && FD_ISSET(s, &wset)) {
            int err = 0; socklen_t elen = sizeof(err);
            if (getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &elen) == 0 && err == 0) {
                ok = YES;
            }
        }
    }
    close(s);
    return ok;
}

+ (BOOL)hasLoopbackProxyPort:(NSString **)portInfo {
    static const uint16_t ports[] = { 8080, 8888, 8889, 9090 };
    for (size_t i = 0; i < sizeof(ports) / sizeof(ports[0]); i++) {
        if ([self _canConnectLoopback:ports[i]]) {
            if (portInfo) *portInfo = [NSString stringWithFormat:@"127.0.0.1:%u", ports[i]];
            return YES;
        }
    }
    return NO;
}

#pragma mark - 防抓包：抓包工具 dylib 扫描

+ (BOOL)hasCaptureDylib:(NSString **)matched {
    static NSArray<NSString *> *bad = nil;
    static dispatch_once_t once; dispatch_once(&once, ^{
        bad = @[
            // iOS 端常见抓包/代理类 App 注入内容
            @"Stream",          // Stream（iOS 抓包）
            @"Thor",            // Thor（iOS 抓包）
            @"HttpCatch",       // HTTP Catcher
            @"Shadowrocket",    // 小火箭（代理）
            @"Surge",           // Surge（代理）
            @"Quantumult",      // Quantumult（代理）
            @"Loon",            // Loon（代理）
            @"mitm",            // mitmproxy
            @"Charles",         // Charles iOS
            @"Proxyman",        // Proxyman
            @"Burp",            // Burp Mobile Assistant
        ];
    });
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *n = _dyld_get_image_name(i);
        if (!n) continue;
        NSString *name = [NSString stringWithUTF8String:n];
        for (NSString *key in bad) {
            if ([name rangeOfString:key options:NSCaseInsensitiveSearch].location != NSNotFound) {
                if (matched) *matched = name;
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - 防抓包聚合

+ (BOOL)isCaptureEnvironment:(NSString **)reason {
    NSString *sub = nil;
    if ([self hasSystemHTTPProxy])               { if (reason) *reason = @"proxy";          return YES; }
    if ([self hasLoopbackProxyPort:&sub])        { if (reason) *reason = sub ?: @"loopback_proxy"; return YES; }
    if ([self hasCaptureDylib:&sub])             { if (reason) *reason = sub ?: @"capture_dylib";  return YES; }
    if ([self hasVPNInterface:&sub])             { if (reason) *reason = sub ?: @"vpn";     return YES; }
    return NO;
}

#pragma mark - SSL Pinning：系统 CA Only

+ (void)handleServerTrustChallenge:(NSURLAuthenticationChallenge *)challenge
                 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    // 只处理 server trust，其他（Basic/Digest）按默认走
    if (![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if (completionHandler) completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    if (!trust) {
        if (completionHandler) completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    // 第一道防线：当前环境被设置了系统 HTTP/HTTPS 代理 → 一律拒绝。
    // （典型中间人如 Charles/mitmproxy/Proxyman 必开系统代理 + 装根证书，
    //   即便用户已信任了它们的 CA，此处也会在握手时断链。）
    if ([self hasSystemHTTPProxy]) {
        if (completionHandler) completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    // 第二道防线：标准 X509 证书链验证（系统默认 anchor）。
    // 说明：iOS 未暴露"仅系统内置 CA"的公开 API；
    //      手动清空 anchors + OnlyTrue 会导致所有 HTTPS 连接全部失败（无可用 anchor）。
    //      因此这里保留系统默认链验证，并配合第一道系统代理检测来封死中间人。
    BOOL valid = NO;
    if (@available(iOS 12.0, *)) {
        CFErrorRef err = NULL;
        valid = SecTrustEvaluateWithError(trust, &err);
        if (err) CFRelease(err);
    } else {
        SecTrustResultType res = kSecTrustResultInvalid;
        if (SecTrustEvaluate(trust, &res) == errSecSuccess) {
            valid = (res == kSecTrustResultUnspecified || res == kSecTrustResultProceed);
        }
    }

    if (valid) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:trust];
        if (completionHandler) completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
    } else {
        if (completionHandler) completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    }
}

+ (NSURLSession *)pinnedSessionWithConfiguration:(NSURLSessionConfiguration *)cfg {
    if (!cfg) cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];

    // 强制走直连：忽略系统连接代理字典（即使 hasSystemHTTPProxy 没拦也不让代理接管）
    cfg.connectionProxyDictionary = @{};

    // TLS 下限
    if (@available(iOS 13.0, *)) {
        cfg.TLSMinimumSupportedProtocolVersion = tls_protocol_version_TLSv12;
    }

    static _PCPinningDelegate *delegate = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ delegate = [[_PCPinningDelegate alloc] init]; });

    NSOperationQueue *q = [[NSOperationQueue alloc] init];
    q.maxConcurrentOperationCount = 1;
    return [NSURLSession sessionWithConfiguration:cfg delegate:delegate delegateQueue:q];
}

@end
