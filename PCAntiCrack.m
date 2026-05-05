//
//  PCAntiCrack.m
//  PersonalCenterUI
//

#import "PCAntiCrack.h"
#import "PCAuthCrypto.h"
#import <sys/types.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <CommonCrypto/CommonCrypto.h>

typedef int (*ptrace_ptr_t)(int _request, pid_t _pid, caddr_t _addr, int _data);
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif

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

@end
