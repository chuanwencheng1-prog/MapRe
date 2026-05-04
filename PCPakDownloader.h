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

/// 下载并复制 pak 到自定义目标目录（使用 .m 顶部配置区的默认 URL；
/// 保存文件名一律使用下载完成后系统从 HTTP 响应中解析出的原始文件名）
/// @param title    业务标签（仅用于日志与弹窗标题，不影响下载逻辑）
/// @param progress 下载进度回调（主线程）
/// @param completion 完成回调（主线程）
- (void)startDownloadWithTitle:(NSString *)title
                      progress:(nullable PCPakProgressBlock)progress
                    completion:(nullable PCPakCompletionBlock)completion;

/// 同上，但本次下载临时覆盖直链（用于「每个确定按钮独立一条直链」）。
/// 保存文件名仍一律使用下载完成后 NSURLResponse.suggestedFilename 的原始文件名，
/// urlString 为 nil / 空 → 回退到 kPCPakDownloadURL。
/// 其余逻辑（Bundle ID 扫描、落盘子目录、覆盖策略）完全一致。
- (void)startDownloadWithTitle:(NSString *)title
                   overrideURL:(nullable NSString *)urlString
                      progress:(nullable PCPakProgressBlock)progress
                    completion:(nullable PCPakCompletionBlock)completion;

/// 取消当前下载
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
