//
//  PCAntiCrack.m
//  PersonalCenterUI
//

#import "PCAntiCrack.h"
#import "PCAuthCrypto.h"
#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CFNetwork/CFNetwork.h>

typedef int (*ptrace_ptr_t)(int _request, pid_t _pid, caddr_t _addr, int _data);
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif

@implementation PCAntiCrack

+ (void)denyAttach {
    // 通过 dlsym 调用 ptrace，避免把符号写进导入表
    // 非越狱环境下 ptrace 可能导致进程被杀，先检测环境
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile"]) return; // 非越狱环境跳过
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/lib/substrate"] &&
        ![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/lib/TweakInject"] &&
        ![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) return; // 无越狱标志跳过
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

#pragma mark - 抓包/代理/VPN 检测

/// 检测 1：系统代理配置（Charles / Burp / mitmproxy 等抓包工具通常会设置系统 HTTP 代理）
+ (BOOL)_hasSystemProxy:(NSString **)detail {
    CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
    if (!proxySettings) return NO;
    NSDictionary *ps = (__bridge_transfer NSDictionary *)proxySettings;

    // HTTP 代理
    BOOL httpEnabled = [[ps objectForKey:(__bridge NSString *)kCFNetworkProxiesHTTPEnable] boolValue];
    NSString *httpHost = [ps objectForKey:(__bridge NSString *)kCFNetworkProxiesHTTPProxy];
    if (httpEnabled && httpHost.length > 0) {
        if (detail) *detail = [NSString stringWithFormat:@"HTTP代理:%@:%@", httpHost, ps[(__bridge NSString *)kCFNetworkProxiesHTTPPort] ?: @"?"];
        return YES;
    }

    // HTTPS 代理
    BOOL httpsEnabled = [[ps objectForKey:@"HTTPSEnable"] boolValue];
    NSString *httpsHost = [ps objectForKey:@"HTTPSProxy"];
    if (httpsEnabled && httpsHost.length > 0) {
        if (detail) *detail = [NSString stringWithFormat:@"HTTPS代理:%@:%@", httpsHost, ps[@"HTTPSPort"] ?: @"?"];
        return YES;
    }

    // SOCKS 代理（iOS 上这些 key 字符串虽未导出符号，但字典中仍可能存在）
    BOOL socksEnabled = [[ps objectForKey:@"SOCKSEnable"] boolValue];
    NSString *socksHost = [ps objectForKey:@"SOCKSProxy"];
    if (socksEnabled && socksHost.length > 0) {
        if (detail) *detail = [NSString stringWithFormat:@"SOCKS代理:%@", socksHost];
        return YES;
    }

    return NO;
}

/// 检测 2：VPN / 隧道网卡接口（报文抓取工具如 Surge/Shadowrocket 会创建 utun 接口）
+ (BOOL)_hasVPNInterface:(NSString **)detail {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return NO;

    static NSArray<NSString *> *vpnPrefixes = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        vpnPrefixes = @[@"utun", @"ipsec", @"ppp", @"tap", @"tun"];
    });

    BOOL found = NO;
    struct ifaddrs *cur = interfaces;
    while (cur != NULL) {
        NSString *name = [NSString stringWithUTF8String:cur->ifa_name ?: ""];
        // 跳过 utun0（系统默认 IPv6 隧道），从 utun1 开始算可疑
        if ([name isEqualToString:@"utun0"]) { cur = cur->ifa_next; continue; }
        for (NSString *prefix in vpnPrefixes) {
            if ([name hasPrefix:prefix]) {
                if (detail) *detail = [NSString stringWithFormat:@"VPN接口:%@", name];
                found = YES;
                break;
            }
        }
        if (found) break;
        cur = cur->ifa_next;
    }
    freeifaddrs(interfaces);
    return found;
}

/// 检测 3：常见抓包工具监听端口（本地探测 TCP connect）
+ (BOOL)_hasSnifferPort:(NSString **)detail {
    // 常见抓包工具的默认端口
    static const int ports[] = { 8888, 8889, 9090, 9091, 8080, 8081, 6152, 6153, 6170 };
    // Charles:8888/8889 mitmproxy:9090/9091 Burp:8080/8081 Surge:6152/6153/6170
    static const int portCount = sizeof(ports) / sizeof(ports[0]);

    for (int i = 0; i < portCount; i++) {
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) continue;

        // 设置非阻塞超时（很短，仅探测本地）
        struct timeval tv = { .tv_sec = 0, .tv_usec = 50000 }; // 50ms
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(ports[i]);
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

        int ret = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
        close(sock);

        if (ret == 0) {
            if (detail) *detail = [NSString stringWithFormat:@"本地端口%d开放", ports[i]];
            return YES;
        }
    }
    return NO;
}

/// 检测 4：越狱环境下扫描抓包相关进程
+ (BOOL)_hasSnifferProcess:(NSString **)detail {
    // 非越狱环境无权限枚举其他进程，直接跳过
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile"] &&
        ![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
        return NO;
    }
    // 注：仅在越狱环境下有权限枚举其他进程
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0) return NO;
    if (size == 0) return NO;

    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(size);
    if (!procs) return NO;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) {
        free(procs);
        return NO;
    }
    int count = (int)(size / sizeof(struct kinfo_proc));

    static NSArray<NSString *> *badNames = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        badNames = @[
            @"tcpdump",
            @"charlesproxy", @"Charles",
            @"mitmproxy", @"mitmdump", @"mitmweb",
            @"Proxyman",
            @"wireshark", @"tshark",
            @"Burp", @"BurpSuite",
            @"snoop", @"HTTPAnalyzer",
            @"thor", @"Thor",
        ];
    });

    BOOL found = NO;
    for (int i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:procs[i].kp_proc.p_comm ?: ""];
        if (name.length == 0) continue;
        for (NSString *bad in badNames) {
            if ([name rangeOfString:bad options:NSCaseInsensitiveSearch].location != NSNotFound) {
                if (detail) *detail = [NSString stringWithFormat:@"抓包进程:%@", name];
                found = YES;
                break;
            }
        }
        if (found) break;
    }
    free(procs);
    return found;
}

+ (BOOL)isSniffingDetected {
    return [self isSniffingDetected:nil];
}

+ (BOOL)isSniffingDetected:(NSString **)reason {
    NSString *r = nil;
    if ([self _hasSystemProxy:&r])     { if (reason) *reason = r; return YES; }
    if ([self _hasVPNInterface:&r])     { if (reason) *reason = r; return YES; }
    if ([self _hasSnifferPort:&r])      { if (reason) *reason = r; return YES; }
    if ([self _hasSnifferProcess:&r])   { if (reason) *reason = r; return YES; }
    return NO;
}

@end
