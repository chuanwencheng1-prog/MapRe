//
//  Tweak.xm
//  PersonalCenterUI
//
//  dylib 入口：
//    通过 %ctor（等价 __attribute__((constructor)) / +load）
//    监听 UIApplicationDidFinishLaunchingNotification，
//    在 keyWindow 上 present PCMainViewController 作为“第一屏”。
//
//  【本次修复】激活时概率性重启/闪退（仅做必要的并发串行化）：
//    - 原实现有两条触发路径（didFinishLaunching 通知 + 1.5s 兜底 dispatch_after），
//      并发 present 时若 Filza 处于模态动画或 UIAlertController 栈中，
//      会触发 CoreAnimation 异常或 “Presenting on detached VC” 崩溃。
//    - 仅使用原子标志做串行防重入；top VC 只过滤 UIAlertController（必须）。
//    - 不再添加其它启动期过滤，避免影响正常 UI 显示。
//

#import <UIKit/UIKit.h>
#import <libkern/OSAtomic.h>
#import "PCMainViewController.h"

// 全局原子标志：防止两条触发路径（launch 通知 + 兜底 dispatch_after）并发 present
static volatile int32_t gPCPresenting = 0;      // 正在 present 中
static volatile int32_t gPCPresented  = 0;      // 已经成功 present 过主 VC

static void PCPresentMainWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 已经成功 present 过 → 直接放弃
        if (gPCPresented) return;
        // 正在 present 中 → 直接放弃（另一条路径在跑）
        if (!OSAtomicCompareAndSwap32(0, 1, &gPCPresenting)) return;

        // 兼容 iOS 13+ 多 scene / iOS 12 及以下 keyWindow
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] &&
                    scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                        if (w.isKeyWindow) { keyWindow = w; break; }
                    }
                    if (!keyWindow && ((UIWindowScene *)scene).windows.count > 0) {
                        keyWindow = ((UIWindowScene *)scene).windows.firstObject;
                    }
                    if (keyWindow) break;
                }
            }
        }
        if (!keyWindow) {
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
        }
        if (!keyWindow) {
            gPCPresenting = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
            return;
        }

        UIViewController *root = keyWindow.rootViewController;
        if (!root) {
            gPCPresenting = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
            return;
        }

        // 走到最顶层的 presented VC
        UIViewController *top = root;
        while (top.presentedViewController) top = top.presentedViewController;

        // 已经是主 VC，不重复 present
        if ([top isKindOfClass:[PCMainViewController class]]) {
            gPCPresented = 1;
            gPCPresenting = 0;
            return;
        }

        // 若 top 正在 present/dismiss 动画中，延迟重试，避免状态错乱
        if (top.isBeingPresented || top.isBeingDismissed) {
            gPCPresenting = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
            return;
        }

        // 过滤 UIAlertController：不能在 Alert 上 present fullScreen（iOS 会崩）
        if ([top isKindOfClass:[UIAlertController class]]) {
            gPCPresenting = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
            return;
        }

        @try {
            PCMainViewController *vc = [[PCMainViewController alloc] init];
            vc.modalPresentationStyle = UIModalPresentationFullScreen;
            [top presentViewController:vc animated:NO completion:^{
                gPCPresented = 1;
                gPCPresenting = 0;
            }];
        } @catch (NSException *ex) {
            NSLog(@"[PersonalCenterUI] present 异常：%@", ex);
            gPCPresenting = 0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
        }
    });
}

%ctor {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification * _Nonnull note) {
            // 稍微延迟以保证 rootViewController 已就绪
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
        }];

        // 兜底：若注入发生在 didFinishLaunching 之后（进程已启动），延长到 1.5s
        // PCPresentMainWindow 内部用原子标志防重入，与上面的通知触发路径不会重复 present
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PCPresentMainWindow();
        });
    }
}
