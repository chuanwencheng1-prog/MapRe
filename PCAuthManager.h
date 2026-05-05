//
//  PCAuthManager.h
//  PersonalCenterUI
//
//  客户端验证中枢：
//    · bootstrap             启动时自动校验（本地缓存 + 心跳）
//    · activateWithCode:     首次激活 / 补激活
//    · heartbeat             周期心跳（默认 5 分钟）
//    · isActivated           供 UI/下载器调用的同步只读开关
//    · signOut               踢出本机
//
//  防破解：
//    · 所有网络请求 HMAC 签名 + AES 加密；响应 RSA 公钥验签
//    · 本地缓存文件 AES 加密，密钥派生自设备指纹（换机即失效）
//    · 缓存含 hmac 字段自校验，脏读直接清空
//    · isActivated 每次都会校验 expireAt / fingerprint 一致性
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^PCAuthCompletion)(BOOL success, NSString * _Nullable message);

@interface PCAuthManager : NSObject

+ (instancetype)sharedManager;

/// 启动握手：有本地激活缓存 → 尝试心跳；无 → 回调 success=NO（外层应弹激活框）。
- (void)bootstrapWithCompletion:(PCAuthCompletion)completion;

/// 首次激活（或更换激活码）
- (void)activateWithCode:(NSString *)code completion:(PCAuthCompletion)completion;

/// 当前是否处于"激活态且未过期"。同步方法，可在下载前多点校验。
- (BOOL)isActivated;

/// 手动发起心跳（内部已由定时器周期触发）
- (void)heartbeat;

/// 本地退出（清除缓存，下次启动需重新激活）
- (void)signOut;

/// 只读信息（用于 UI 展示）
- (NSDate * _Nullable)boundUntil;
- (NSString *)deviceFingerprint;

@end

NS_ASSUME_NONNULL_END
