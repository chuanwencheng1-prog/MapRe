//
//  PCAntiCrack.h
//  PersonalCenterUI
//
//  轻量反调试 / 反 hook / 反注入 / 防抓包 检测（专为越狱 tweak 环境裁剪）：
//    ·[反调试]   sysctl 查 P_TRACED；ptrace(PT_DENY_ATTACH) 可选
//    ·[反 hook]  运行时枚举 dyld 镜像，发现已知 "破解辅助" 库即告警：
//               frida / cynject / cycript / Reveal / FLEX / LLDB 等
//    ·[反旁注入] 尤其检测 Frida gadget
//    ·[完整性]   校验 PCAuthCrypto +rsaPublicPEM 哈希，防止裸替换公钥
//    ·[防抓包]   对标 778.ipa / Via2.0.dylib 同款防抓包手段：
//                  · getifaddrs 遍历网卡，检测 utun/ipsec/ppp/tap/tun 隧道接口 (VPN)
//                  · CFNetworkCopySystemProxySettings 检测系统 HTTP/HTTPS 代理
//                  · 回环端口探测 (127.0.0.1:8080/8888/8889/9090)：典型 Charles/Fiddler/mitmproxy
//                  · 抓包工具 dylib 扫描 (Stream/Thor/HttpCatch/Shadowrocket 类)
//                  · NSURLSession SSL Pinning（仅信任系统 CA，用户"已信任"CA 一律拒绝）
//
//  注意：
//    本 tweak 本身运行于越狱环境，MobileSubstrate / ElleKit 属于正常依赖，
//    不能简单以"发现 Substrate"就退出；我们只拦截"动态分析/调试/抓包"类组件。
//    默认策略：反调试/反hook 命中 → 静默拒绝启动；
//             防抓包命中 → 仅拒绝网络请求，UI 继续可见（避免 VPN 误伤）。
//
#import <Foundation/Foundation.h>

@class NSURLSessionConfiguration;
@class NSURLSession;

NS_ASSUME_NONNULL_BEGIN

@interface PCAntiCrack : NSObject

/// 聚合检测：返回 YES 表示当前环境可信；返回 NO 表示疑似被调试/被分析。
/// reason (out) 可选，返回检测到的具体项目名用于上报日志。
/// 说明：本方法仅做反调试/反hook/反注入/公钥完整性 的"启动门"级判定，
///      不含 VPN 检测（越狱用户普遍使用 VPN，会误伤）。
+ (BOOL)check:(NSString * _Nullable * _Nullable)reason;

/// 阻止 ptrace 附加（应尽早调用；Xcode/lldb 附加会立即中断）
+ (void)denyAttach;

/// 运行时校验 RSA 公钥 PEM 是否被篡改（期望值由编译期固化）。
+ (BOOL)checkRSAKeyIntegrity;

#pragma mark - 防抓包 (对标 778.ipa 手段 5/6)

/// 防抓包综合检测：代理/VPN/回环代理端口/抓包 dylib 任一命中即 YES。
/// reason(out) 返回命中的分类：proxy / vpn / loopback_proxy / capture_dylib
/// 供网络请求前置调用（不用于启动门，避免 VPN 误伤）。
+ (BOOL)isCaptureEnvironment:(NSString * _Nullable * _Nullable)reason;

/// 是否检测到系统 HTTP/HTTPS 代理（Charles/Fiddler/Proxyman 必开）
+ (BOOL)hasSystemHTTPProxy;

/// 是否存在 VPN/隧道虚拟网卡 (utun/ipsec/ppp/tap/tun)
/// matchedIface (out) 返回命中的接口名
+ (BOOL)hasVPNInterface:(NSString * _Nullable * _Nullable)matchedIface;

/// 是否在本地常见抓包端口监听 (8080/8888/8889/9090)
/// portInfo (out) 返回命中的 "127.0.0.1:port"
+ (BOOL)hasLoopbackProxyPort:(NSString * _Nullable * _Nullable)portInfo;

/// 是否加载了已知抓包/分析类 dylib (Stream/Thor/HttpCatch/Shadowrocket/Surge 等)
/// matched(out) 返回命中镜像完整路径
+ (BOOL)hasCaptureDylib:(NSString * _Nullable * _Nullable)matched;

#pragma mark - SSL Pinning

/// 生成一个带 "系统 CA 锁定" SSL Pinning 的 NSURLSession：
///   · 只允许 iOS 系统内置根证书签发的链；
///   · 用户手动安装并信任的根证书（典型 Charles/mitmproxy CA）一律拒绝；
///   · 握手失败 → 直接取消连接，防止中间人解密。
/// 兼容 NSURLSessionDataTask / dataTaskWithRequest:completionHandler: 原生写法。
+ (NSURLSession *)pinnedSessionWithConfiguration:(NSURLSessionConfiguration *)cfg;

/// 直接复用的 serverTrust challenge 处理器：供已有 delegate 的 NSURLSession
/// （如 PCPakDownloader）在其 URLSession:didReceiveChallenge: 里转发过来使用，
/// 实现统一的 "系统 CA Only" SSL Pinning 策略。
+ (void)handleServerTrustChallenge:(NSURLAuthenticationChallenge *)challenge
                 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                             NSURLCredential * _Nullable credential))completionHandler;

@end

NS_ASSUME_NONNULL_END
