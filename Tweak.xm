//
//  Tweak.xm
//  PersonalCenterUI
//
//  dylib 入口：
//    通过 %ctor（等价 __attribute__((constructor)) / +load）
//    监听 UIApplicationDidFinishLaunchingNotification，
//    在 keyWindow 上 present PCMainViewController 作为"第一屏"。
//
//  说明：此方案与 yy1.ipa 中 vianeitou0.dylib 一致
//       （见《yy1_ipa_分析报告.txt》第二、三节），
//       但剥离了针对"和平精英"沙盒扫描与下发的全部逻辑，
//       仅保留"启动显示自定义 UI + 点击下载并复制文件到用户自定义路径"的合规部分。
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

        // 如果已经 present 过就不重复弹
        if ([root.presentedViewController isKindOfClass:[PCMainViewController class]]) return;
        UIViewController *top = root;
        while (top.presentedViewController) top = top.presentedViewController;
        if ([top isKindOfClass:[PCMainViewController class]]) return;

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

        // 兜底：若注入发生在 didFinishLaunching 之后（进程已启动），直接尝试 present
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PCPresentMainWindow();
        });
    }
}
