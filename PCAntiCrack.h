//
//  PCAntiCrack.h
//  PersonalCenterUI
//
//  轻量反调试 / 反 hook / 反注入 检测（专为越狱 tweak 环境裁剪）：
//    ·[反调试] sysctl 查 P_TRACED；ptrace(PT_DENY_ATTACH) 可选
//    ·[反 hook] 运行时枚举 dyld 镜像，发现已知 "破解辅助" 库即告警：
//              frida / cynject / cycript / Reveal / FLEX / LLDB 等
//    ·[反越狱插件旁注入] 尤其检测 Frida gadget
//    ·[完整性自检] 校验 PCAuthCrypto +rsaPublicPEM 哈希，防止裸替换公钥
//
//  注意：
//    本 tweak 本身运行于越狱环境，MobileSubstrate / ElleKit 属于正常依赖，
//    不能简单以"发现 Substrate"就退出；我们只拦截"动态分析/调试"类组件。
//
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface PCAntiCrack : NSObject

/// 聚合检测：返回 YES 表示当前环境可信；返回 NO 表示疑似被调试/被分析。
/// reason (out) 可选，返回检测到的具体项目名用于上报日志。
+ (BOOL)check:(NSString * _Nullable * _Nullable)reason;

/// 阻止 ptrace 附加（应尽早调用；Xcode/lldb 附加会立即中断）
+ (void)denyAttach;

/// 运行时校验 RSA 公钥 PEM 是否被篡改（期望值由编译期固化）。
+ (BOOL)checkRSAKeyIntegrity;

@end

NS_ASSUME_NONNULL_END
