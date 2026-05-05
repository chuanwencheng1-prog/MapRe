//
//  PCDeviceID.h
//  PersonalCenterUI
//
//  iOS 越狱环境下的真·UDID 读取器
//
//  说明：
//    · Apple 从 iOS 7 起禁用 -[UIDevice uniqueIdentifier]，App Store 上架即被拒。
//      但本工程仅在越狱设备上部署，MobileGestalt 私有 API 可用：
//        CFStringRef MGCopyAnswer(CFStringRef property);
//      它可以读取 iOS 设备上的"真 UDID"（40位十六进制），
//      重装系统 / 卸装重装 App 都不会变——真正的"设备唯一标识"。
//
//    · 为避免 Apple static analyzer 与 strings 工具发现 MGCopyAnswer 字面符号，
//      采用 dlopen(libMobileGestalt) + dlsym(MGCopyAnswer) 动态解析；
//      参数 "UniqueDeviceID" 也在运行时拼接而成。
//
//    · 如果 MobileGestalt 不可用（非越狱、或系统裁剪），
//      会逐级降级到：
//        1) /var/root/.../device_uuid 这类常见缓存（部分 jb 写了）
//        2) IDFV + 机型 + 系统 组成的稳定哈希（至少不闪退、可用）
//      所有路径都经过 strnlen/nil 保护，绝对不会闪退。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PCDeviceID : NSObject

/// 取真 UDID（40 位十六进制小写）。读取失败时返回稳定派生串（非 nil，非空）。
+ (NSString *)udid;

/// 当前 UDID 来源（debug/日志用）。
///   real       : MobileGestalt UniqueDeviceID（真 UDID）
///   jailbreak  : 越狱文件缓存
///   derived    : IDFV + 机型 + 系统 派生（降级）
+ (NSString *)source;

@end

NS_ASSUME_NONNULL_END
