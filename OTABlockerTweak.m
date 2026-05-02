//
//  OTABlockerTweak.m
//  dylib 入口：在宿主 App 启动瞬间把 OTABlockerViewController
//  作为第一屏覆盖到 keyWindow 上。
//
//  编译成 dylib 后，放进 .app 目录，通过 insert_dylib 给宿主主二进制
//  追加一条 LC_LOAD_WEAK_DYLIB @executable_path/xxx.dylib 即可生效。
//

#import <UIKit/UIKit.h>
#import "OTABlockerViewController.h"

@interface OTABlockerTweak : NSObject
@end

@implementation OTABlockerTweak

+ (void)load {
    // +load 比 main 更早执行，这里只做注册，UI 创建要等到
    // UIApplicationDidFinishLaunchingNotification 再做，
    // 否则拿不到 keyWindow。
    [[NSNotificationCenter defaultCenter]
        addObserver:[self class]
           selector:@selector(presentOverlay)
               name:UIApplicationDidFinishLaunchingNotification
             object:nil];
}

+ (void)presentOverlay {
    // 延迟到下一个 runloop，确保 rootViewController 已创建
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [OTABlockerTweak findKeyWindow];
        UIViewController *root = keyWindow.rootViewController;
        if (!root) {
            // 兜底：稍后再试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [OTABlockerTweak presentOverlay];
            });
            return;
        }

        OTABlockerViewController *vc = [[OTABlockerViewController alloc] init];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;

        // 找到栈顶，从栈顶 present，避免 root 正在被 present 时崩溃
        UIViewController *top = root;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:vc animated:NO completion:nil];
    });
}

+ (UIWindow *)findKeyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
            // 没有 keyWindow 时返回该 scene 的第一个可见 window
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (!w.hidden) return w;
            }
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

@end
