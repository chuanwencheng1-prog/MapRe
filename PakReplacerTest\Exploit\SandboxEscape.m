// SandboxEscape.m
// 沙盒逃逸实现
// 对应原始 PakReplacer 中的环境检测与沙盒绕过逻辑

#import "SandboxEscape.h"
#import "KFDExploit.h"
#import "CicutaVirosa.h"
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <mach/mach.h>

// ============================================================
// MARK: - 环境检测
// ============================================================

BOOL sandbox_is_trollstore(void)
{
    // 对应原始代码检测 TrollStore 路径
    NSArray<NSString *> *trollPaths = @[
        @"/Applications/TrollStore.app",
        @"/var/jb/Applications/TrollStore.app",
        @"/var/containers/Bundle/Application/TrollStore.app",
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in trollPaths) {
        if ([fm fileExistsAtPath:path]) {
            NSLog(@"[Sandbox] TrollStore 检测到: %@", path);
            return YES;
        }
    }
    return NO;
}

BOOL sandbox_is_jailbroken(void)
{
    // 越狱标志文件检测（对应原始代码越狱检测逻辑）
    NSArray<NSString *> *jailbreakPaths = @[
        @"/var/jb/usr/bin/bash",
        @"/var/jb/usr/libexec/jailbreakd",
        @"/usr/bin/apt",
        @"/Applications/Cydia.app",
        @"/private/var/lib/apt/",
        @"/var/jb/.installed_dopamine",
        @"/var/jb/.installed_palera1n",
        @"/private/preboot/jb",
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in jailbreakPaths) {
        if ([fm fileExistsAtPath:path]) {
            NSLog(@"[Sandbox] 越狱环境检测到: %@", path);
            return YES;
        }
    }

    // 检测越狱写入能力
    NSString *testPath = @"/private/jailbreak_test";
    NSError *err = nil;
    [@"test" writeToFile:testPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!err) {
        [[NSFileManager defaultManager] removeItemAtPath:testPath error:nil];
        return YES;
    }

    return NO;
}

BOOL sandbox_detect_frida(void)
{
    // 对应原始代码 Frida 检测
    NSArray<NSString *> *fridaPaths = @[
        @"/usr/sbin/frida-server",
        @"/var/jb/usr/sbin/frida-server",
        @"/usr/bin/frida-trace",
        @"/usr/lib/frida/frida-agent.dylib",
        @"/var/jb/usr/lib/frida",
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in fridaPaths) {
        if ([fm fileExistsAtPath:path]) {
            NSLog(@"[Sandbox] Frida 检测到: %@", path);
            return YES;
        }
    }

    // 检测 frida 注入的动态库
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "frida")) {
            NSLog(@"[Sandbox] Frida dylib 注入检测: %s", name);
            return YES;
        }
    }

    return NO;
}

// ============================================================
// MARK: - 沙盒逃逸
// ============================================================

BOOL sandbox_escape(void)
{
    // 策略1: TrollStore 环境（已有跨沙盒访问权限）
    if (sandbox_is_trollstore()) {
        NSLog(@"[Sandbox] TrollStore 环境，直接访问无需逃逸");
        return YES;
    }

    // 策略2: 越狱环境
    if (sandbox_is_jailbroken()) {
        NSLog(@"[Sandbox] 越狱环境，已无沙盒限制");
        return YES;
    }

    // 策略3: KFD 内核权限 → 修改当前进程 sandbox token
    if (kfd_is_active()) {
        NSLog(@"[Sandbox] 使用 KFD 内核权限进行沙盒逃逸...");

        // 通过修改 proc->p_ucred->cr_label 清除沙盒 MAC label
        // 具体实现需按 iOS 版本确定偏移
        // 参考 Fugu15 / Dopamine sandbox_escape 实现

        // 简化版：尝试直接访问目标路径（KFD已修改vnode权限）
        NSString *testPath = @"/var/mobile/Containers/Data/Application/";
        NSError *err = nil;
        NSArray *contents = [[NSFileManager defaultManager]
                             contentsOfDirectoryAtPath:testPath error:&err];
        if (contents && !err) {
            NSLog(@"[Sandbox] KFD 沙盒逃逸成功，容器数量: %lu", (unsigned long)contents.count);
            return YES;
        }
    }

    // 策略4: cicuta_virosa 内核权限
    if (cicuta_virosa_is_active()) {
        NSLog(@"[Sandbox] 使用 cicuta_virosa 内核权限进行沙盒逃逸...");
        // 同 KFD 策略
        NSString *testPath = @"/var/mobile/Containers/Data/Application/";
        NSError *err = nil;
        NSArray *contents = [[NSFileManager defaultManager]
                             contentsOfDirectoryAtPath:testPath error:&err];
        if (contents && !err) {
            NSLog(@"[Sandbox] cicuta_virosa 沙盒逃逸成功");
            return YES;
        }
    }

    NSLog(@"[Sandbox] 沙盒逃逸失败，需要 TrollStore/越狱/内核权限");
    return NO;
}

// ============================================================
// MARK: - 容器路径查找
// ============================================================

NSString *sandbox_find_game_container(NSString *bundleID)
{
    if (!bundleID) return nil;

    NSString *containersBase = @"/var/mobile/Containers/Data/Application/";
    NSError *err = nil;
    NSArray *uuids = [[NSFileManager defaultManager]
                      contentsOfDirectoryAtPath:containersBase error:&err];

    if (err || !uuids) {
        NSLog(@"[Sandbox] 无法读取容器目录（沙盒限制）: %@", err.localizedDescription);
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *uuid in uuids) {
        NSString *metaPath = [NSString stringWithFormat:
            @"%@%@/.com.apple.mobile_container_manager.metadata.plist",
            containersBase, uuid];

        if (![fm fileExistsAtPath:metaPath]) continue;

        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        NSString *bid = meta[@"MCMMetadataIdentifier"];
        if ([bid isEqualToString:bundleID]) {
            NSString *docsPath = [NSString stringWithFormat:
                @"%@%@/Documents", containersBase, uuid];
            NSLog(@"[Sandbox] 找到 %@ 容器: %@", bundleID, docsPath);
            return docsPath;
        }
    }

    NSLog(@"[Sandbox] 未找到 %@ 的容器", bundleID);
    return nil;
}

NSString *sandbox_get_pak_directory(NSString *bundleID, NSString *subPath)
{
    NSString *container = sandbox_find_game_container(bundleID);
    if (!container) return nil;

    NSString *pakDir = [container stringByAppendingPathComponent:subPath];
    NSLog(@"[Sandbox] PAK 目录: %@", pakDir);
    return pakDir;
}
