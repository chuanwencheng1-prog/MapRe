//
//  PCAntiCrack.h
//  PersonalCenterUI
//
//  全方位反破解 / 反调试 / 反抓包 防御（越狱 tweak 定制裁剪）：
//
//    [ A. 反调试 ]
//      · sysctl 查 P_TRACED
//      · ptrace(PT_DENY_ATTACH) 阻断 lldb/debugserver 附加
//      · task_info MACH_EXCEPTION_PORTS 端口被占探测（进阶）
//
//    [ B. 反 Hook / 反注入 ]
//      · 运行时枚举 dyld 镜像，命中黑名单（frida / cycript / cynject / Reveal / FLEX 等）
//      · DYLD_INSERT_LIBRARIES 白名单（仅允许 Substrate/ElleKit 等 tweak 基础设施）
//
//    [ C. 反抓包 / 反中间人 ]
//      · 系统代理（HTTP/HTTPS/SOCKS）检测 —— Charles / Proxyman / Fiddler / mitmproxy
//      · VPN 接口检测 —— utun / ipsec / ppp / tap / tun（Shadowrocket / Surge 等抓 HTTPS）
//      · SSL Kill Switch / tweak 类 dylib 检测
//
//    [ D. 完整性自检 ]
//      · 校验 PCAuthCrypto +rsaPublicPEM 字节 SHA-256 与编译期哈希一致
//
//    策略：严重项（抓包/VPN/调试/注入分析）触发 +crashAndExit，
//          进程立即 abort()，绝不泄漏任何直链。
//          完整性篡改返回 NO 让启动器拒绝进入主界面。
//
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface PCAntiCrack : NSObject

/// 聚合检测：YES = 可信环境；NO = 不可信（reason 会输出命中项）。
+ (BOOL)check:(NSString * _Nullable * _Nullable)reason;

/// 抓包/VPN 专项检测（独立接口，供网络请求前实时调用）。
///   returnYES = 正常；NO = 发现抓包或 VPN，reason 返回具体类型
+ (BOOL)checkProxyAndVPN:(NSString * _Nullable * _Nullable)reason;

/// 阻止 ptrace 附加（应尽早调用；Xcode/lldb 附加会立即中断）。
+ (void)denyAttach;

/// 运行时校验 RSA 公钥 PEM 是否被篡改（期望值由编译期固化）。
+ (BOOL)checkRSAKeyIntegrity;

/// 一键执行"判定 + 闪退"。检测到任何严重问题（抓包/VPN/frida 等）直接 abort()。
/// 调用点：dylib %ctor、网络请求前、敏感操作前。
/// reasonOut 可选，用于在 abort 前把命中项写到日志。
+ (void)crashIfEnvCompromised:(NSString * _Nullable * _Nullable)reasonOut;

@end

NS_ASSUME_NONNULL_END
