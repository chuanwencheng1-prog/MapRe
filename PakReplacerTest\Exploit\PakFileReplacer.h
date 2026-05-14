// PakFileReplacer.h
// PAK 文件替换核心接口
// 统一调度: MDC → KFD → 直接写入 三级策略

#ifndef PakFileReplacer_h
#define PakFileReplacer_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef NS_ENUM(NSInteger, PakReplaceStrategy) {
    PakReplaceStrategyAuto   = 0,  // 自动选择最佳策略
    PakReplaceStrategyMDC    = 1,  // 强制 CVE-2022-46689
    PakReplaceStrategyKFD    = 2,  // 强制 KFD
    PakReplaceStrategyCicuta = 3,  // 强制 cicuta_virosa
    PakReplaceStrategyDirect = 4,  // 直接写入（沙盒内）
};

typedef void (^PakReplaceProgress)(float progress, NSString *log);
typedef void (^PakReplaceCompletion)(BOOL success, NSString *message, NSString *strategy);

@interface PakFileReplacer : NSObject

/**
 * 替换单个 PAK 文件（核心入口）
 * @param localPath    本地缓存的 PAK 路径（沙盒内）
 * @param targetPath   游戏目录中的目标 PAK 路径
 * @param strategy     替换策略（推荐 Auto）
 * @param progress     进度回调（主线程）
 * @param completion   完成回调（主线程）
 */
+ (void)replacePak:(NSString *)localPath
        targetPath:(NSString *)targetPath
          strategy:(PakReplaceStrategy)strategy
          progress:(PakReplaceProgress)progress
        completion:(PakReplaceCompletion)completion;

/**
 * 批量替换 PAK 文件
 * @param pairs   @[ @{@"local": ..., @"target": ...} ] 数组
 */
+ (void)replacePakBatch:(NSArray<NSDictionary *> *)pairs
               strategy:(PakReplaceStrategy)strategy
               progress:(PakReplaceProgress)progress
             completion:(PakReplaceCompletion)completion;

/**
 * 备份目标 PAK 到沙盒（还原时使用）
 * @param targetPath  要备份的 PAK 路径
 * @return 备份文件路径，失败返回 nil
 */
+ (NSString *)backupPak:(NSString *)targetPath;

/**
 * 从备份恢复 PAK 文件
 * @param backupPath  备份文件路径
 * @param targetPath  还原目标路径
 */
+ (void)restorePak:(NSString *)backupPath
        targetPath:(NSString *)targetPath
        completion:(PakReplaceCompletion)completion;

/**
 * 获取推荐策略名称（根据当前 iOS 版本）
 */
+ (NSString *)recommendedStrategyName;

@end

#ifdef __cplusplus
}
#endif

#endif /* PakFileReplacer_h */
