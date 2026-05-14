// CicutaVirosa.h
// cicuta_virosa iOS 内核漏洞接口
// 适用 iOS 15.0 ~ 15.4.1
// 原理: IOSurface IOSF UAF → 内核任意读写

#ifndef CicutaVirosa_h
#define CicutaVirosa_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 启动 cicuta_virosa 漏洞利用
 * @return 0=成功，获得内核读写原语
 */
int cicuta_virosa_run(void);

/**
 * 清理 cicuta_virosa 资源
 */
void cicuta_virosa_cleanup(void);

/**
 * 检测 cicuta_virosa 是否激活
 */
BOOL cicuta_virosa_is_active(void);

/**
 * 检测当前 iOS 版本是否支持 cicuta_virosa
 */
BOOL cicuta_virosa_is_supported(void);

/**
 * 使用 cicuta_virosa 内核权限覆写文件
 */
BOOL cicuta_virosa_overwrite_file(const char *src, const char *dst);

// ============================================================
// MARK: - ObjC 封装
// ============================================================

typedef void (^CVProgressBlock)(float progress, NSString *log);
typedef void (^CVCompletionBlock)(BOOL success, NSString *message);

@interface CicutaVirosaRunner : NSObject

+ (void)overwritePak:(NSString *)localPakPath
          targetPath:(NSString *)targetPakPath
            progress:(CVProgressBlock)progress
          completion:(CVCompletionBlock)completion;

@end

#ifdef __cplusplus
}
#endif

#endif /* CicutaVirosa_h */
