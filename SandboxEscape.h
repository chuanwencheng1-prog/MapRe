// SandboxEscape.h
// 沙盒逃逸接口
// 配合 KFD/cicuta_virosa 内核权限访问游戏数据目录

#ifndef SandboxEscape_h
#define SandboxEscape_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 检测是否在 TrollStore 环境运行（已有沙盒外权限）
 */
BOOL sandbox_is_trollstore(void);

/**
 * 检测是否在越狱环境（完全无沙盒）
 */
BOOL sandbox_is_jailbroken(void);

/**
 * 检测是否存在 Frida（反调试）
 */
BOOL sandbox_detect_frida(void);

/**
 * 使用内核权限逃逸沙盒
 * 依赖 kfd_is_active() 或 cicuta_virosa_is_active()
 * 成功后可访问 /var/mobile/Containers/Data/Application/ 任意应用目录
 */
BOOL sandbox_escape(void);

/**
 * 检测目标游戏容器 UUID（ShadowTrackerExtra）
 * 原始代码中硬编码了 UUID，此函数动态查找
 * @param bundleID  目标游戏 Bundle ID
 * @return 游戏 Documents 目录绝对路径，失败返回 nil
 */
NSString *sandbox_find_game_container(NSString *bundleID);

/**
 * 获取游戏 PAK 目录路径
 * @param bundleID  游戏 Bundle ID（如 com.netease.ShadowTrackerExtra）
 * @param subPath   PAK 子路径（如 Saved/Paks）
 */
NSString *sandbox_get_pak_directory(NSString *bundleID, NSString *subPath);

#ifdef __cplusplus
}
#endif

#endif /* SandboxEscape_h */
