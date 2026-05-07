//
//  PCPakDownloader.h
//  PersonalCenterUI
//
//  pak 文件下载器（下载 + 复制到用户自定义路径）
//  沿用 yy1.ipa 分析报告中的实现思路（见报告第四节的
//    downloadAndCopyPakFileWithURL:toDestination:completion:），
//  但剥离了针对其它 App 沙盒扫描、账号验证、自动卸载等全部红线逻辑。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^PCPakProgressBlock)(double progress, int64_t received, int64_t total);
typedef void(^PCPakCompletionBlock)(BOOL success,
                                    NSString * _Nullable finalPath,
                                    NSError * _Nullable error);

@interface PCPakDownloader : NSObject

+ (instancetype)sharedDownloader;

/// 下载并复制 pak 到自定义目标目录
/// @param title    业务标签（仅用于日志与弹窗标题，不影响下载逻辑）
/// @param progress 下载进度回调（主线程）
/// @param completion 完成回调（主线程）
- (void)startDownloadWithTitle:(NSString *)title
                      progress:(nullable PCPakProgressBlock)progress
                    completion:(nullable PCPakCompletionBlock)completion;

/// 取消当前下载
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
