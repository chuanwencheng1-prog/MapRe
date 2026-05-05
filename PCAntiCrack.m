//
//  PCAntiCrack.m
//  PersonalCenterUI
//

#import "PCAntiCrack.h"
#import "PCAuthCrypto.h"
#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CFNetwork/CFProxySupport.h>
#import <SystemConfiguration/SystemConfiguration.h>

typedef int (*ptrace_ptr_t)(int _request, pid_t _pid, caddr_t _addr, int _data);
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif

@implementation PCAntiCrack

#pragma mark - A. 反调试

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

#pragma mark - B. 反 hook / 反注入

+ (BOOL)_hasSuspiciousDylib:(NSString **)matched {
    // 只匹配"动态分析/调试/抓包/SSL 剖析"类组件，不拦 MobileSubstrate 等 tweak 基础设施
    static NSArray<NSString *> *bad = nil;
    static dispatch_once_t once; dispatch_once(&once, ^{
        bad = @[
            // --- 动态分析 / Hook ---
            @"FridaGadget",
            @"frida-agent",
            @"libfrida",
            @"cycript",
            @"cynject",
            @"RevealServer",
            @"libReveal",
            @"FLEXLoader",
            @"libsubstitute-loader",  // 调试用重注入
            // --- SSL 剖析 ---
            @"SSLKillSwitch",   // iOS SSL pinning bypass（Charles/Proxyman 常配）
            @"SSLBypass",
            @"TrustMeAlready",
            @"libsslbypass",
            // --- 逆向 / 砸壳 / 抓包 tweak ---
            @"HTTPCatcher",
            @"Thor",            // iOS 抓包 tweak
            @"Stream.dylib",
            @"libhooker.dylib",
            @"zzz-mitm",
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

#pragma mark - C. 反抓包 / 反中间人 —— 系统代理检测

/// 返回 YES = 系统被设置了 HTTP/HTTPS/SOCKS 代理（Charles / Proxyman / Fiddler / mitmproxy 等）。
+ (BOOL)_hasSystemProxy:(NSString **)matched {
    CFDictionaryRef settings = CFNetworkCopySystemProxySettings();
    if (!settings) return NO;

    BOOL hit = NO;
    // HTTPEnable / HTTPSEnable
    for (NSString *flag in @[@"HTTPEnable", @"HTTPSEnable", @"SOCKSEnable",
                             (NSString *)kCFNetworkProxiesHTTPEnable,
                             (NSString *)kCFNetworkProxiesHTTPProxy,
                             (NSString *)kCFNetworkProxiesHTTPPort]) {
        CFTypeRef v = CFDictionaryGetValue(settings, (__bridge CFStringRef)flag);
        if (!v) continue;
        if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            int n = 0;
            CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n);
            if (n != 0) { hit = YES; if (matched) *matched = flag; break; }
        } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
            NSString *s = (__bridge NSString *)(CFStringRef)v;
            if (s.length > 0) { hit = YES; if (matched) *matched = [NSString stringWithFormat:@"%@=%@", flag, s]; break; }
        }
    }
    CFRelease(settings);
    return hit;
}

#pragma mark - C. 反抓包 —— VPN 接口检测

/// 返回 YES = 当前系统存在 VPN / 代理隧道接口（utun、ipsec、ppp、tap、tun）。
/// 这些接口常被 Shadowrocket/Surge/Quantumult 等"全局代理 + MITM"App 使用。
+ (BOOL)_hasVPNInterface:(NSString **)matched {
    struct ifaddrs *ifs = NULL;
    if (getifaddrs(&ifs) != 0 || ifs == NULL) return NO;

    // 匹配前缀：这些就是 iOS 上典型的"抓 HTTPS 型 VPN/代理"接口名
    NSArray<NSString *> *prefixes = @[ @"tap", @"tun", @"ppp", @"ipsec", @"utun" ];

    BOOL hit = NO;
    for (struct ifaddrs *cur = ifs; cur; cur = cur->ifa_next) {
        if (!cur->ifa_name) continue;
        NSString *name = [NSString stringWithUTF8String:cur->ifa_name] ?: @"";
        for (NSString *p in prefixes) {
            if ([name hasPrefix:p]) {
                // utun0 是 iOS 的 Personal Hotspot / iCloud Relay 内部，误报率较高
                // 我们只在 utun ≥ 1 或其它类型时命中。iCloud Relay 固定使用 utun0。
                if ([name isEqualToString:@"utun0"]) break;
                if (matched) *matched = name;
                hit = YES;
                break;
            }
        }
        if (hit) break;
    }
    freeifaddrs(ifs);
    return hit;
}

#pragma mark - 聚合入口

+ (BOOL)checkProxyAndVPN:(NSString * _Nullable * _Nullable)reason {
    NSString *m = nil;
    if ([self _hasSystemProxy:&m]) {
        if (reason) *reason = [NSString stringWithFormat:@"proxy(%@)", m ?: @"?"];
        return NO;
    }
    if ([self _hasVPNInterface:&m]) {
        if (reason) *reason = [NSString stringWithFormat:@"vpn(%@)", m ?: @"?"];
        return NO;
    }
    return YES;
}

+ (BOOL)check:(NSString **)reason {
    NSString *r = nil;
    if ([self _isBeingTraced])                  { if (reason) *reason = @"traced";     return NO; }
    if ([self _hasSuspiciousDylib:&r])          { if (reason) *reason = r ?: @"dylib"; return NO; }
    if ([self _hasEnvDebug])                    { if (reason) *reason = @"dyld_env";   return NO; }
    if (![self checkProxyAndVPN:&r])            { if (reason) *reason = r ?: @"mitm";  return NO; }
    if (![self checkRSAKeyIntegrity])           { if (reason) *reason = @"rsa_tamper"; return NO; }
    return YES;
}

+ (void)crashIfEnvCompromised:(NSString * _Nullable * _Nullable)reasonOut {
    NSString *r = nil;
    if ([self check:&r]) return;

    if (reasonOut) *reasonOut = r;
    NSLog(@"[PersonalCenterUI][AntiCrack] compromised env: %@ -> abort()", r ?: @"unknown");

    // 清掉所有痕迹并强制 abort。
    //   · 不直接 exit(0)：对方可以 hook exit；abort() 会 raise SIGABRT，
    //     即使 hook 了 SIGABRT handler，进入 handler 后再 abort 一次也会杀掉进程。
    //   · 加一个"异常地址写"兜底，防止所有 signal handler 都被 hook 住。
    abort();
    // 到这里理论上已经不会执行；再写一个必定崩溃的指令兜底
    volatile int *p = (int *)0x0;
    *p = 0xDEAD;
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

@end
