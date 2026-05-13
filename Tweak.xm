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
#import "PCAuthPopView.h"
#import "PCAuthManager.h"

// 授权门禁宿主 VC：仅承载卡密弹窗，本身全透明 / 黑底
@interface PCAuthGateVC : UIViewController
@property (nonatomic, strong) PCAuthPopView *pop;
@property (nonatomic, copy)   void (^onAuthorized)(void);
@end
@implementation PCAuthGateVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.pop) return;
    self.pop = [[PCAuthPopView alloc] init];
    __weak typeof(self) ws = self;
    [self.pop presentFromVC:self onAuthorized:^{
        __strong typeof(ws) ss = ws;
        if (!ss) return;
        void (^cb)(void) = ss.onAuthorized;
        [ss dismissViewControllerAnimated:NO completion:^{
            if (cb) cb();
        }];
    }];
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
@end

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

        // 如已挂过门禁 VC 不重复
        if ([top isKindOfClass:[PCAuthGateVC class]]) return;

        void (^presentMain)(UIViewController *) = ^(UIViewController *onTop){
            PCMainViewController *vc = [[PCMainViewController alloc] init];
            vc.modalPresentationStyle = UIModalPresentationFullScreen;
            [onTop presentViewController:vc animated:NO completion:^{
                // 启动心跳：到期 / 服务器踢人 → 弹警告 + 关闭主 VC 强制重新激活
                [[PCAuthManager sharedManager] startHeartbeatWithInterval:300 onKicked:^(NSString * _Nullable reason) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[PCAuthManager sharedManager] stopHeartbeat];
                        UIAlertController *al = [UIAlertController
                            alertControllerWithTitle:@"授权失效"
                                             message:reason ?: @"授权已到期，需重新激活"
                                      preferredStyle:UIAlertControllerStyleAlert];
                        [al addAction:[UIAlertAction actionWithTitle:@"重新激活" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
                            [vc dismissViewControllerAnimated:NO completion:^{
                                PCPresentMainWindow();
                            }];
                        }]];
                        UIViewController *topV = vc;
                        while (topV.presentedViewController) topV = topV.presentedViewController;
                        [topV presentViewController:al animated:YES completion:nil];
                    });
                }];
            }];
        };

        PCAuthGateVC *gate = [[PCAuthGateVC alloc] init];
        gate.modalPresentationStyle = UIModalPresentationOverFullScreen;
        gate.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        __weak PCAuthGateVC *wg = gate;
        gate.onAuthorized = ^{
            UIViewController *p = wg.presentingViewController;
            // 授权通过后走原来的主 VC
            presentMain(p ?: top);
        };
        [top presentViewController:gate animated:YES completion:nil];
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
