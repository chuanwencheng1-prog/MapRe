//
//  PCAuthManager.h
//  PersonalCenterUI
//
//  卡密授权管理器：
//    - 设备指纹一机一码（identifierForVendor + Keychain 持久化兜底，重装不丢）
//    - 卡密激活 / 在线验证 / 心跳续期
//    - 服务器返回 RSA(SHA256) 签名 → 客户端用硬编码公钥验签（防中间人/抓包篡改）
//    - 本地缓存授权凭证（NSUserDefaults + Keychain），离线启动时优先校验到期时间
//
//  ========================================================================
//  ★ 必改：把下面三项改成你自己的服务器
//  1) kPCAuthServerBase  —— 例 "https://your.domain.com/pc_auth"
//  2) kPCAuthAppID       —— 后台"系统设置"里 APP_ID 保持一致
//  3) kPCAuthPubKeyPEM   —— 安装向导生成后复制 public.pem 全部内容
//  ========================================================================
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PCAuthStatus) {
    PCAuthStatusUnknown       = 0,
    PCAuthStatusValid         = 1,   // 已授权有效
    PCAuthStatusExpired       = 2,   // 已到期
    PCAuthStatusInvalid       = 3,   // 卡密无效 / 已禁用
    PCAuthStatusDeviceMismatch= 4,   // 卡密已绑定其它设备
    PCAuthStatusNetwork       = 5,   // 网络异常
    PCAuthStatusSignatureBad  = 6,   // 签名校验失败（可能被中间人）
    PCAuthStatusNotActivated  = 7,   // 未激活
};

typedef void(^PCAuthCompletion)(PCAuthStatus status,
                                NSTimeInterval expiresAt,   // UTC 秒
                                NSString * _Nullable message);

@interface PCAuthManager : NSObject

+ (instancetype)sharedManager;

/// 当前设备唯一机器码（SHA256 16进制，32字节）
- (NSString *)deviceID;

/// 已缓存的卡密（无则 nil）
- (nullable NSString *)cachedCardKey;

/// 已缓存的到期 UTC 秒（0 = 无）
- (NSTimeInterval)cachedExpiresAt;

/// 本地快速校验：有有效缓存且未过期 → YES
- (BOOL)isLocallyAuthorized;

/// 使用卡密激活（首次）
- (void)activateWithCard:(NSString *)card
              completion:(PCAuthCompletion)completion;

/// 在线校验（二次启动 / 心跳）
- (void)verifyWithCompletion:(PCAuthCompletion)completion;

/// 清掉本地缓存（调试用）
- (void)clearCache;

/// 启动心跳（默认 5 分钟一次）：本地到期或服务器返回失效 → onKicked 回调
- (void)startHeartbeatWithInterval:(NSTimeInterval)seconds
                         onKicked:(void(^)(NSString * _Nullable reason))onKicked;

/// 停止心跳
- (void)stopHeartbeat;

#pragma mark - 远程菜单配置

/// 拉取服务器远程菜单配置（签名校验过）
/// completion.config 成功时为 JSON（包含 key "menus"）；失败时为 nil + error
- (void)fetchRemoteConfigWithCompletion:(void(^)(NSDictionary * _Nullable config,
                                                  NSError * _Nullable error))completion;

/// 本地缓存的远程菜单配置（供首屏秒打开渲染）
- (nullable NSDictionary *)cachedRemoteConfig;

@end

NS_ASSUME_NONNULL_END
