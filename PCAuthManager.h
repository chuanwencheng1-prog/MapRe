//
//  PCAuthManager.h
//  PersonalCenterUI
//
//  客户端验证中枢：
//    · bootstrap             启动时自动校验（本地缓存 + 心跳 + 探活）
//    · activateWithCode:     首次激活 / 补激活
//    · heartbeat             周期心跳（默认 5 分钟）
//    · isActivated           供 UI / 下载器调用的同步只读开关
//    · isServerOnline        供 UI 判断是否该"隐藏所有直链布局"
//    · signOut               踢出本机（不 crash，只清缓存 + 发通知）
//
//  防破解：
//    · 所有网络请求 HMAC 签名 + AES 加密；响应 RSA 公钥验签
//    · 每次网络请求前 [PCAntiCrack crashIfEnvCompromised:] —— 抓包/VPN/调试/Frida 即闪退
//    · 本地缓存文件 AES 加密，密钥派生自真 UDID（换机即失效，卸装重装免重激活）
//    · 缓存含 HMAC 自校验，脏读直接清空
//    · isActivated 每次都会校验 expireAt / UDID 一致性
//    · 到期 / 被踢下线：signOut() 而非 abort()——不会闪退，UI 收到通知后弹激活框
//
//  通知：
//    · PCAuthStatusDidChangeNotification    状态变化（激活 / 失效 / 服务器离线 / 在线）
//      userInfo:
//        @"activated"  : @(BOOL)
//        @"online"     : @(BOOL)
//        @"reason"     : NSString*   ("expired" / "kicked" / "offline" / "online" / "activated")
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^PCAuthCompletion)(BOOL success, NSString * _Nullable message);

FOUNDATION_EXPORT NSString *const PCAuthStatusDidChangeNotification;

@interface PCAuthManager : NSObject

+ (instancetype)sharedManager;

/// 启动握手：先 ping 探活 → 已激活则心跳 → 无本地缓存回调 success=NO。
- (void)bootstrapWithCompletion:(PCAuthCompletion)completion;

/// 首次激活（或更换激活码）
- (void)activateWithCode:(NSString *)code completion:(PCAuthCompletion)completion;

/// 当前是否处于"激活态且未过期"。同步方法，可在下载前多点校验。
- (BOOL)isActivated;

/// 服务器是否可达（bootstrap / heartbeat 最近一次结果）。
/// · 首次启动未获得结果前返回 NO（保守策略：默认视为离线，界面保持空白）。
/// · 连续 N 次心跳失败后也会置为 NO，用于"服务器关闭即清空所有直链布局"。
- (BOOL)isServerOnline;

/// 手动发起心跳（内部已由定时器周期触发）
- (void)heartbeat;

/// 本地退出（清除缓存，不闪退，下次启动需重新激活）
- (void)signOut;

/// 只读信息（用于 UI 展示）
- (NSDate * _Nullable)boundUntil;
- (NSString *)deviceFingerprint;   // 现在内部就是 UDID
- (NSString *)deviceUDID;          // 明确暴露 UDID 给后台查询 / 调试
- (NSString *)udidSource;          // "real"/"jailbreak"/"derived"

@end

NS_ASSUME_NONNULL_END
