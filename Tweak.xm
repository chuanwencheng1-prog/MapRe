//
//  Tweak.xm
//  PersonalCenterUI
//
//  dylib 入口：
//    通过 %ctor（等价 __attribute__((constructor)) / +load）
//    监听 UIApplicationDidFinishLaunchingNotification，
//    在 keyWindow 上 present PCMainViewController 作为"第一屏"。
//
//  授权流程（修复版）：
//    1. 先 present PCMainViewController（插件主 UI）到 Filza 的 rootViewController
//    2. 在 PCMainViewController.viewDidAppear: 内部检查授权，未授权时
//       在 自己的 view 上 addSubview 卡密弹窗 —— 此时弹窗背景就是插件 UI
//    3. 避免了嵌套 present/dismiss，修复了激活成功后的状态错乱闪退
//

#import <UIKit/UIKit.h>
#import "PCMainViewController.h"

static void PCPresentMainWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
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
        if (!keyWindow) return;

        UIViewController *root = keyWindow.rootViewController;
        if (!root) return;

        // 走到最顶层的 presented VC
        UIViewController *top = root;
        while (top.presentedViewController) top = top.presentedViewController;

        // 已经是主 VC，不重复 present
        if ([top isKindOfClass:[PCMainViewController class]]) return;

        // 若 top 正在 present/dismiss 动画中，延迟重试，避免状态错乱
        if (top.isBeingPresented || top.isBeingDismissed) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PCPresentMainWindow();
            });
            return;
        }

        PCMainViewController *vc = [[PCMainViewController alloc] init];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:vc animated:NO completion:nil];
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
        // 避免与 0.3s 的主触发在动画中打架
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PCPresentMainWindow();
        });
    }
}
