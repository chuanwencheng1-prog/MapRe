//
//  Tweak.xm
//  PersonalCenterUI
//
//  dylib 入口：
//    通过 %ctor（等价 __attribute__((constructor)) / +load）
//    监听 UIApplicationDidFinishLaunchingNotification，
//    在 keyWindow 上 present PCMainViewController 作为“第一屏”。
//
//  【本轮修复】启动期概率性“重启手机”（实际是 Springboard 看门狗 / app 启动崩）的根因加固：
//    1. 进程白名单：只在宏主 App 主进程生效，过滤 .appex 扩展 / XPC helper / daemon。
//       Filza 启动时会拉起多个子进程（如预览、分享扩展），这些进程并没有
//       UIApplication / UIScene 上下文，在其中访问 connectedScenes / sharedApplication
//       可能 EXC_BAD_ACCESS → SpringBoard 重启 / app 冷启动崩溃。
//    2. 启动状态闸：仅在 application.applicationState == Active
//       且 keyWindow.rootViewController.view.window 就绪后才 present，
//       避免“启动过早 present”触发 CoreAnimation NSInternalInconsistencyException。
//    3. 兑底不再无条件跳：仅在未收到 didFinishLaunching 通知时才运作，
//       避免与通知路径同时跳 + 递归重试冲击栈。
//    4. 全部 scene / window 枚举包 @try/@catch，任何异常不往外抛。
//    5. 限制最大重试次数，防止启动期递归不收敛。
//    6. observer token 保存并在首次 present 后移除，避免 block 保留外部对象。
//

#import <UIKit/UIKit.h>
#import <libkern/OSAtomic.h>
#import "PCMainViewController.h"

// 全局原子标志：防止两条触发路径（launch 通知 + 兑底 dispatch_after）并发 present
static volatile int32_t gPCPresenting       = 0;   // 正在 present 中
static volatile int32_t gPCPresented        = 0;   // 已经成功 present 过主 VC
static volatile int32_t gPCDidFinishLaunch  = 0;   // didFinishLaunching 通知是否已到达
static volatile int32_t gPCRetryCount       = 0;   // 重试计数
static id  gPCLaunchObserver  = nil;               // observer token强引
static id  gPCActiveObserver  = nil;               // didBecomeActive observer token

// 允许的最大重试次数（各种原因期间合计）—— 超过后不再调度，避免启动期递归不收敛
static const int32_t kPCMaxRetryCount = 30;

#pragma mark - 进程白名单

/// 是否运行在宏主 App 的主进程（非 .appex 扩展 / 非 XPC helper / 存在 UIApplication）
static BOOL PCIsHostMainProcess(void) {
    @try {
        // 1) 排除 app extension（bundle path 含 .appex）
        NSString *bp = [NSBundle mainBundle].bundlePath ?: @"";
        if ([bp.lowercaseString hasSuffix:@".appex"]) return NO;
        if ([bp rangeOfString:@".appex/" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;

        // 2) 主 bundle 必须是 Application 类型（infoDictionary CFBundlePackageType == APPL）
        NSString *pkg = [[NSBundle mainBundle].infoDictionary[@"CFBundlePackageType"]
                         isKindOfClass:[NSString class]]
                       ? [NSBundle mainBundle].infoDictionary[@"CFBundlePackageType"] : @"";
        if (![pkg isEqualToString:@"APPL"]) return NO;

        // 3) UIApplication 类本身必须已加载（daemon / XPC 进程通常不链接 UIKit）
        Class appCls = NSClassFromString(@"UIApplication");
        if (!appCls) return NO;
        if (![appCls respondsToSelector:@selector(sharedApplication)]) return NO;
        // 使用 IMP 调用避免 performSelector 警告
        UIApplication *(*sharedApp)(Class, SEL) =
            (UIApplication *(*)(Class, SEL))[appCls methodForSelector:@selector(sharedApplication)];
        if (!sharedApp) return NO;
        UIApplication *app = sharedApp(appCls, @selector(sharedApplication));
        if (!app) return NO;

        return YES;
    } @catch (__unused NSException *ex) {
        return NO;
    }
}

#pragma mark - keyWindow 获取（全 try/catch）

static UIWindow *PCFindKeyWindowSafe(void) {
    UIWindow *keyWindow = nil;
    @try {
        if (@available(iOS 13.0, *)) {
            NSSet *scenes = [UIApplication sharedApplication].connectedScenes;
            for (UIScene *scene in scenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                if (scene.activationState != UISceneActivationStateForegroundActive) continue;
                UIWindowScene *ws = (UIWindowScene *)scene;
                NSArray<UIWindow *> *wins = ws.windows;
                for (UIWindow *w in wins) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
                if (!keyWindow && wins.count > 0) keyWindow = wins.firstObject;
                if (keyWindow) break;
            }
        }
    } @catch (__unused NSException *ex) { keyWindow = nil; }

    if (!keyWindow) {
        @try {
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
        } @catch (__unused NSException *ex) { keyWindow = nil; }
    }
    return keyWindow;
}

#pragma mark - present 主逻辑

static void PCSchedulePresentRetry(NSTimeInterval delay);

static void PCPresentMainWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 已成功过 → 直接退出
        if (gPCPresented) return;
        // 重试次数上限保护
        if (gPCRetryCount > kPCMaxRetryCount) return;
        // 只在宏主主进程运行
        if (!PCIsHostMainProcess()) return;
        // 串行闸：同一时刻只让一个路径进入 present
        if (!OSAtomicCompareAndSwap32(0, 1, &gPCPresenting)) return;

        // 必须为 Active 状态才能安全 present。
        // 启动期多为 Inactive，过早 present 会触发多种 CA 崩溃。
        UIApplication *app = nil;
        @try { app = [UIApplication sharedApplication]; } @catch (__unused NSException *ex) {}
        if (!app || app.applicationState != UIApplicationStateActive) {
            gPCPresenting = 0;
            PCSchedulePresentRetry(0.4);
            return;
        }

        UIWindow *keyWindow = PCFindKeyWindowSafe();
        if (!keyWindow) {
            gPCPresenting = 0;
            PCSchedulePresentRetry(0.4);
            return;
        }

        UIViewController *root = keyWindow.rootViewController;
        // root 未加载 / view 未上屏 → 继续等
        if (!root || !root.isViewLoaded || root.view.window == nil) {
            gPCPresenting = 0;
            PCSchedulePresentRetry(0.4);
            return;
        }

        // 走到最顶层的 presented VC
        UIViewController *top = root;
        @try {
            while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
                top = top.presentedViewController;
            }
        } @catch (__unused NSException *ex) { top = root; }

        // 已经是主 VC，不重复 present
        if ([top isKindOfClass:[PCMainViewController class]]) {
            gPCPresented = 1;
            gPCPresenting = 0;
            return;
        }

        // top 正在 present/dismiss 动画 → 延迟重试
        if (top.isBeingPresented || top.isBeingDismissed) {
            gPCPresenting = 0;
            PCSchedulePresentRetry(0.4);
            return;
        }

        // 不能在 UIAlertController 上 present fullScreen
        if ([top isKindOfClass:[UIAlertController class]]) {
            gPCPresenting = 0;
            PCSchedulePresentRetry(0.6);
            return;
        }

        // top.view 未上屏（脱离 keyWindow）→ 重试
        if (!top.isViewLoaded || top.view.window == nil) {
            gPCPresenting = 0;
            PCSchedulePresentRetry(0.4);
            return;
        }

        @try {
            PCMainViewController *vc = [[PCMainViewController alloc] init];
            vc.modalPresentationStyle = UIModalPresentationFullScreen;
            [top presentViewController:vc animated:NO completion:^{
                gPCPresented = 1;
                gPCPresenting = 0;
                // 首次成功 present 后移除 observer，避免 block 保留
                @try {
                    if (gPCLaunchObserver) {
                        [[NSNotificationCenter defaultCenter] removeObserver:gPCLaunchObserver];
                        gPCLaunchObserver = nil;
                    }
                    if (gPCActiveObserver) {
                        [[NSNotificationCenter defaultCenter] removeObserver:gPCActiveObserver];
                        gPCActiveObserver = nil;
                    }
                } @catch (__unused NSException *ex) {}
            }];
        } @catch (NSException *ex) {
            NSLog(@"[PersonalCenterUI] present 异常：%@", ex);
            gPCPresenting = 0;
            PCSchedulePresentRetry(1.0);
        }
    });
}

static void PCSchedulePresentRetry(NSTimeInterval delay) {
    if (gPCPresented) return;
    int32_t cur = OSAtomicIncrement32(&gPCRetryCount);
    if (cur > kPCMaxRetryCount) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        PCPresentMainWindow();
    });
}

%ctor {
    @autoreleasepool {
        // 【进程白名单】不是宏主主进程直接退出——这是“启动重启”的首要防线。
        // 不能依赖 Theos INSTALL_TARGET_PROCESSES：Filza 启动过程中仍有可能拉起
        // 带 .appex 后缀的扩展进程，启动期同样会被同名 dylib 加载。
        if (!PCIsHostMainProcess()) {
            return;
        }

        gPCLaunchObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification * _Nonnull note) {
            OSAtomicCompareAndSwap32(0, 1, &gPCDidFinishLaunch);
            // 小延迟，等 rootViewController 、第一屏 UI 就绪
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
        }];

        // 附加 didBecomeActive 触发路径：启动后由 inactive → active 是 present 的最佳时机
        gPCActiveObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification * _Nonnull note) {
            // active 事件也走同样的入口，与 launch 通知互不冲突（原子标志防重入）
            PCPresentMainWindow();
        }];

        // 【兑底】只在 1.5s 后“未收到 didFinishLaunching”且未成功 present 时才跳，
        // 避免与通知路径重复调度。【同时】进 PCPresentMainWindow 会再次严格校验
        // applicationState，未进入 Active 不会真正 present。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (gPCPresented) return;
            if (gPCDidFinishLaunch) return; // 通知路径已接管
            PCPresentMainWindow();
        });
    }
}
