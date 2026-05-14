// PakFileReplacer.m
// PAK 文件替换核心实现
// 三级策略: MDC(CVE-2022-46689) → KFD → 直接写入

#import "PakFileReplacer.h"
#import "MDCExploit.h"
#import "KFDExploit.h"
#import "CicutaVirosa.h"
#import <Foundation/Foundation.h>

// 备份目录（沙盒 Documents/PakBackup/）
static NSString *backupDir(void) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [docs stringByAppendingPathComponent:@"PakBackup"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return dir;
}

@implementation PakFileReplacer

// ============================================================
// MARK: - 核心替换入口
// ============================================================

+ (void)replacePak:(NSString *)localPath
        targetPath:(NSString *)targetPath
          strategy:(PakReplaceStrategy)strategy
          progress:(PakReplaceProgress)progress
        completion:(PakReplaceCompletion)completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

        // 日志辅助块
        void (^log)(float, NSString *) = ^(float p, NSString *s) {
            NSLog(@"%@", s);
            if (progress) {
                dispatch_async(dispatch_get_main_queue(), ^{ progress(p, s); });
            }
        };
        void (^done)(BOOL, NSString *, NSString *) = ^(BOOL ok, NSString *msg, NSString *strat) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(ok, msg, strat); });
            }
        };

        // 检查源文件
        if (![[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
            done(NO, @"本地 PAK 文件不存在，请先下载", @"None");
            return;
        }

        log(0.05f, [NSString stringWithFormat:@"[Replacer] 开始替换: %@", targetPath.lastPathComponent]);

        // Step1: 备份原文件
        NSString *backup = [self backupPak:targetPath];
        if (backup) {
            log(0.10f, [NSString stringWithFormat:@"[Replacer] 已备份原文件: %@", backup.lastPathComponent]);
        }

        // Step2: 确定实际策略
        PakReplaceStrategy actualStrategy = strategy;
        if (strategy == PakReplaceStrategyAuto) {
            actualStrategy = [self autoSelectStrategy];
        }

        NSString *strategyName = [self strategyName:actualStrategy];
        log(0.15f, [NSString stringWithFormat:@"[Replacer] 使用策略: %@", strategyName]);

        // Step3: 执行写入
        switch (actualStrategy) {

            case PakReplaceStrategyMDC: {
                [MDCExploitRunner overwritePak:localPath
                                    targetPath:targetPath
                                      progress:^(float p, NSString *s) { log(0.15f + p * 0.75f, s); }
                                    completion:^(BOOL ok, NSString *msg) {
                    done(ok, msg, @"MDC (CVE-2022-46689)");
                }];
                break;
            }

            case PakReplaceStrategyKFD: {
                log(0.20f, @"[KFD] 启动 KFD 内核漏洞...");
                [KFDExploitRunner overwritePak:localPath
                                    targetPath:targetPath
                                      progress:^(float p, NSString *s) { log(0.20f + p * 0.70f, s); }
                                    completion:^(BOOL ok, NSString *msg) {
                    done(ok, msg, @"KFD (kexploit_opa334)");
                }];
                break;
            }

            case PakReplaceStrategyCicuta: {
                log(0.20f, @"[Cicuta] 启动 cicuta_virosa 内核漏洞...");
                [CicutaVirosaRunner overwritePak:localPath
                                      targetPath:targetPath
                                        progress:^(float p, NSString *s) { log(0.20f + p * 0.70f, s); }
                                      completion:^(BOOL ok, NSString *msg) {
                    done(ok, msg, @"cicuta_virosa");
                }];
                break;
            }

            case PakReplaceStrategyDirect:
            default: {
                log(0.20f, @"[Direct] 尝试直接写入...");
                BOOL ok = [self directCopy:localPath to:targetPath];
                if (ok) {
                    done(YES, @"直接写入成功", @"Direct");
                } else {
                    done(NO, @"直接写入失败（可能需要 Exploit 权限）", @"Direct");
                }
                break;
            }
        }
    });
}

// ============================================================
// MARK: - 批量替换
// ============================================================

+ (void)replacePakBatch:(NSArray<NSDictionary *> *)pairs
               strategy:(PakReplaceStrategy)strategy
               progress:(PakReplaceProgress)progress
             completion:(PakReplaceCompletion)completion
{
    __block NSInteger total    = pairs.count;
    __block NSInteger current  = 0;
    __block NSInteger failures = 0;

    if (total == 0) {
        if (completion) completion(YES, @"无需替换", @"None");
        return;
    }

    // 串行队列逐一替换
    dispatch_queue_t queue = dispatch_queue_create(
        "com.pakreplacertest.batch", DISPATCH_QUEUE_SERIAL);

    dispatch_async(queue, ^{
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        for (NSDictionary *pair in pairs) {
            NSString *local  = pair[@"local"];
            NSString *target = pair[@"target"];
            current++;

            float baseProgress = (float)(current - 1) / (float)total;

            if (progress) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progress(baseProgress,
                             [NSString stringWithFormat:@"[批量] %ld/%ld: %@",
                              (long)current, (long)total, target.lastPathComponent]);
                });
            }

            [self replacePak:local
                  targetPath:target
                    strategy:strategy
                    progress:nil
                  completion:^(BOOL ok, NSString *msg, NSString *strat) {
                if (!ok) failures++;
                dispatch_semaphore_signal(sem);
            }];

            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        }

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL allOk = (failures == 0);
                NSString *msg = allOk
                    ? [NSString stringWithFormat:@"全部 %ld 个 PAK 替换成功", (long)total]
                    : [NSString stringWithFormat:@"完成 %ld/%ld，%ld 个失败", (long)(total-failures), (long)total, (long)failures];
                completion(allOk, msg, @"Batch");
            });
        }
    });
}

// ============================================================
// MARK: - 备份 & 恢复
// ============================================================

+ (NSString *)backupPak:(NSString *)targetPath
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
        return nil;
    }
    // 用文件名+时间戳命名备份
    NSString *name = [NSString stringWithFormat:@"%@.bak_%ld",
                      targetPath.lastPathComponent,
                      (long)[[NSDate date] timeIntervalSince1970]];
    NSString *dest = [backupDir() stringByAppendingPathComponent:name];

    NSError *err = nil;
    [[NSFileManager defaultManager] copyItemAtPath:targetPath toPath:dest error:&err];
    if (err) {
        NSLog(@"[Backup] 备份失败: %@", err.localizedDescription);
        return nil;
    }
    NSLog(@"[Backup] 备份成功: %@", dest);
    return dest;
}

+ (void)restorePak:(NSString *)backupPath
        targetPath:(NSString *)targetPath
        completion:(PakReplaceCompletion)completion
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:backupPath]) {
        if (completion) completion(NO, @"备份文件不存在", @"Restore");
        return;
    }
    // 使用与替换相同的策略恢复（自动选择）
    [self replacePak:backupPath
          targetPath:targetPath
            strategy:PakReplaceStrategyAuto
            progress:nil
          completion:completion];
}

// ============================================================
// MARK: - 内部辅助
// ============================================================

// 自动策略选择（根据 iOS 版本）
+ (PakReplaceStrategy)autoSelectStrategy
{
    NSOperatingSystemVersion ver =
        [NSProcessInfo processInfo].operatingSystemVersion;
    long major = ver.majorVersion;
    long minor = ver.minorVersion;
    long patch = ver.patchVersion;

    // iOS 16.0 ~ 16.1.2 → MDC 优先
    if (major == 16 && (minor < 1 || (minor == 1 && patch <= 2))) {
        return PakReplaceStrategyMDC;
    }
    // iOS 15.0 ~ 15.4.1 → cicuta_virosa
    if (major == 15 && minor <= 4) {
        return PakReplaceStrategyCicuta;
    }
    // iOS 14.0 ~ 15.x → MDC
    if (major == 14 || major == 15) {
        return PakReplaceStrategyMDC;
    }
    // iOS 16.2 ~ 16.6.1 → KFD
    if (major == 16) {
        return PakReplaceStrategyKFD;
    }
    // 其他 → 直接写入（尝试）
    return PakReplaceStrategyDirect;
}

// 直接文件复制（沙盒内有写权限时使用）
+ (BOOL)directCopy:(NSString *)from to:(NSString *)to
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];

    // 先删除目标（若存在）
    if ([fm fileExistsAtPath:to]) {
        [fm removeItemAtPath:to error:&err];
    }

    return [fm copyItemAtPath:from toPath:to error:&err];
}

+ (NSString *)strategyName:(PakReplaceStrategy)s
{
    switch (s) {
        case PakReplaceStrategyMDC:    return @"MDC (CVE-2022-46689)";
        case PakReplaceStrategyKFD:    return @"KFD (kexploit_opa334)";
        case PakReplaceStrategyCicuta: return @"cicuta_virosa";
        case PakReplaceStrategyDirect: return @"Direct";
        default:                       return @"Auto";
    }
}

+ (NSString *)recommendedStrategyName
{
    return [self strategyName:[self autoSelectStrategy]];
}

@end
