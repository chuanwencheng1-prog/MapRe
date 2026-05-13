//
//  Tweak.xm
//  PersonalCenterUI
//
//  dylib 入口：
//    监听 UIApplicationDidFinishLaunchingNotification，
//    在 keyWindow 上 present PCMainViewController 作为“第一屏”。
//
//  授权流程（修复版）：
//    1. 先 present PCMainViewController（插件主 UI）到 Filza 的 rootViewController
//    2. 在 PCMainViewController.viewDidAppear: 内部检查授权，未授权时
//       在自己的 view 上 addSubview 卡密弹窗
//    3. 避免了嵌套 present/dismiss，修复了激活成功后的状态错乱闪退
//
//  【本次修复】激活时概率性重启/闪退：
//    - 原实现有两条触发路径（didFinishLaunching 通知 + 1.5s 兜底 dispatch_after），
//      并发 present 时若 Filza 处于模态动画或 UIAlertController 栈中，
//      会触发 CoreAnimation 异常或“Presenting on detached VC” 崩溃。
//    - 用原子标志 + 严格的 top VC 过滤 + 挂窗校验做串行防重入。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <libkern/OSAtomic.h>
#import "PCMainViewController.h"

// 全局原子标志：防止两条触发路径（launch 通知 + 兜底 dispatch_after）并发 present
static volatile int32_t gPCPresenting = 0;      // 正在 present 中
static volatile int32_t gPCPresented  = 0;      // 已经成功 present 过主 VC

static BOOL PCIsVCPresentingOrDismissing(UIViewController *vc) {
    if (!vc) return NO;
    if (vc.isBeingPresented || vc.isBeingDismissed) return YES;
    if (vc.isMovingToParentViewController || vc.isMovingFromParentViewController) return YES;
    return NO;
}

static UIWindow *PCFindKeyWindow(void) {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow && !w.hidden) { keyWindow = w; break; }
            }
            if (!keyWindow) {
                for (UIWindow *w in ws.windows) {
                    if (!w.hidden && w.rootViewController) { keyWindow = w; break; }
                }
            }
            if (keyWindow) break;
        }
    }
    if (!keyWindow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow && !w.hidden) { keyWindow = w; break; }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    return keyWindow;
}

static void PCPresentMainWindow(void) {
    // 必须走主线程
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ PCPresentMainWindow(); });
        return;
    }

    // 已经成功 present 过 → 直接放弃
    if (gPCPresented) return;

    // 正在 present 中 → 直接放弃（另一条路径在跑）
    if (!OSAtomicCompareAndSwap32(0, 1, &gPCPresenting)) return;

    @try {
        UIWindow *keyWindow = PCFindKeyWindow();
        if (!keyWindow || !keyWindow.rootViewController) {
            gPCPresenting = 0;
            // 延迟重试一次
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ PCPresentMainWindow(); });
            return;
        }

        UIViewController *root = keyWindow.rootViewController;

        // 走到最顶层的 presented VC
        UIViewController *top = root;
        while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
            top = top.presentedViewController;
        }

        // 已经是主 VC，不重复 present
        if ([top isKindOfClass:[PCMainViewController class]]) {
            gPCPresented = 1;
            gPCPresenting = 0;
            return;
        }

        // 若顶层 VC 正在 present/dismiss 动画中，延迟重试
        if (PCIsVCPresentingOrDismissing(top)) {
            gPCPresenting = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ PCPresentMainWindow(); });
            return;
        }

        // 过滤 UIAlertController：不在 Alert 上 present fullScreen（否则闪退）
        if ([top isKindOfClass:[UIAlertController class]]) {
            gPCPresenting = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ PCPresentMainWindow(); });
            return;
        }

        // top 必须已挂载到 window 才能 present
        if (!top.isViewLoaded || !top.view.window) {
            gPCPresenting = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ PCPresentMainWindow(); });
            return;
        }

        PCMainViewController *vc = [[PCMainViewController alloc] init];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;

        [top presentViewController:vc animated:NO completion:^{
            gPCPresented = 1;
            gPCPresenting = 0;
        }];
    } @catch (NSException *ex) {
        NSLog(@"[PersonalCenterUI] present 异常拦截：%@", ex);
        gPCPresenting = 0;
        // 一段时间后再试，避免崩溃循环
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ PCPresentMainWindow(); });
    }
}

%ctor {
    @autoreleasepool {
        // 只在宿主为前台可交互的 GUI App 中注入，避免极端场景下被 SpringBoard 代理进程引入
        // （filter plist 已限定 Filza，这里是二重兜底）
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (![bundleId isEqualToString:@"com.tigisoftware.Filza"]) {
            // 非目标 App 绝不执行任何 UI / Keychain / 网络逻辑
            return;
        }

        __block id obs = nil;
        obs = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification * _Nonnull note) {
            // 稍微延迟以保证 rootViewController 已就绪
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
            // 一次即可，避免热加载场景重复注册
            if (obs) {
                [[NSNotificationCenter defaultCenter] removeObserver:obs];
                obs = nil;
            }
        }];

        // 兜底：若 dylib 在 didFinishLaunching 之后才被注入（进程已启动），
        // 延迟 1.5s 尝试一次；PCPresentMainWindow 内部用原子标志防重入
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PCPresentMainWindow();
        });
    }
}
