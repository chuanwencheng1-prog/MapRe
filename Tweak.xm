//
//  Tweak.xm
//  PersonalCenterUI
//
//  dylib 入口：
//    1. %ctor 阶段立即 ptrace(PT_DENY_ATTACH)，阻断 lldb/debugserver 附加；
//    2. UIApplicationDidFinishLaunching 后：
//         · 做一次轻量反调试/反 hook 检测（PCAntiCrack）；
//         · 调 PCAuthManager bootstrap 读取本地加密缓存 + 心跳；
//         · 已激活    → present PCMainViewController（主界面）；
//         · 未激活    → present PCActivationViewController（激活弹窗），
//                       onActivated 回调中再切换到主界面；
//         · 校验失败 → 仍弹激活弹窗，强制重新输入激活码。
//
//  说明：保留原 yy1.ipa-vianeitou0.dylib 的"启动即弹窗"模式，
//       仅新增 "未激活禁止进入主界面" 前置闸门，
//       下载行为本身仍在主界面点击后触发，
//       且 PCMainViewController 在执行下载前会再做一次 isActivated 硬校验。
//

#import <UIKit/UIKit.h>
#import "PCMainViewController.h"
#import "PCAuthManager.h"
#import "PCAntiCrack.h"
#import "PCActivationViewController.h"

#pragma mark - Helper

/// 找到当前最上层可用于 present 的 VC
static UIViewController * _Nullable PCTopMostViewController(void) {
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
    if (!keyWindow) return nil;

    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

#pragma mark - Present 主界面

static void PCPresentMainWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = PCTopMostViewController();
        if (!top) return;

        // 幂等：如果当前已经在主界面则不重复弹
        if ([top isKindOfClass:[PCMainViewController class]]) return;
        if ([top.presentedViewController isKindOfClass:[PCMainViewController class]]) return;

        // 多点校验：present 之前再确认一次 isActivated
        if (![[PCAuthManager sharedManager] isActivated]) return;

        PCMainViewController *vc = [[PCMainViewController alloc] init];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:vc animated:NO completion:nil];
    });
}

#pragma mark - Present 激活弹窗

static void PCPresentActivationWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = PCTopMostViewController();
        if (!top) return;

        // 幂等：已经在激活弹窗就不重复弹
        if ([top isKindOfClass:[PCActivationViewController class]]) return;
        if ([top.presentedViewController isKindOfClass:[PCActivationViewController class]]) return;

        // 如果主界面已经 present 过（异常路径：激活态被清除但界面没退），先 dismiss 再弹激活
        if ([top isKindOfClass:[PCMainViewController class]]) {
            [top dismissViewControllerAnimated:NO completion:^{
                PCPresentActivationWindow();
            }];
            return;
        }

        PCActivationViewController *vc = [[PCActivationViewController alloc] init];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        __weak PCActivationViewController *weakVC = vc;
        vc.onActivated = ^{
            // 激活成功：先关闭激活弹窗，再切到主界面
            PCActivationViewController *strongVC = weakVC;
            if (strongVC) {
                [strongVC dismissViewControllerAnimated:YES completion:^{
                    PCPresentMainWindow();
                }];
            } else {
                PCPresentMainWindow();
            }
        };
        [top presentViewController:vc animated:YES completion:nil];
    });
}

#pragma mark - 启动闸门

static void PCBootstrapGate(void) {
    // 先本地快速判断：已激活 → 直接进入主界面（不等网络）；
    // 同时异步 bootstrap 心跳，若服务器踢下线则下次启动自然走激活流程。
    if ([[PCAuthManager sharedManager] isActivated]) {
        PCPresentMainWindow();
        [[PCAuthManager sharedManager] bootstrapWithCompletion:^(BOOL success, NSString * _Nullable message) {
            // 在线心跳：如果远端强制失效，PCAuthManager 内部会清缓存，
            // 这里兜底：再次校验 isActivated，若已失效则弹激活。
            if (!success && ![[PCAuthManager sharedManager] isActivated]) {
                PCPresentActivationWindow();
            }
        }];
        return;
    }

    // 无本地缓存：先尝试 bootstrap（可能只是缓存脏读已被清空），拿不到就弹激活弹窗
    [[PCAuthManager sharedManager] bootstrapWithCompletion:^(BOOL success, NSString * _Nullable message) {
        if (success && [[PCAuthManager sharedManager] isActivated]) {
            PCPresentMainWindow();
        } else {
            PCPresentActivationWindow();
        }
    }];
}

#pragma mark - %ctor

%ctor {
    @autoreleasepool {
        // 1) 尽早 ptrace deny attach，阻断 lldb/debugserver
        [PCAntiCrack denyAttach];

        // 2) 反 hook / 反分析环境校验；检测到则直接拒绝启动闸门（不进入主界面也不弹激活）
        NSString *reason = nil;
        BOOL safeEnv = [PCAntiCrack check:&reason];
        // RSA 公钥完整性自检
        if (safeEnv) safeEnv = [PCAntiCrack checkRSAKeyIntegrity];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification * _Nonnull note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!safeEnv) return; // 不可信环境：静默不弹任何 UI
                PCBootstrapGate();
            });
        }];

        // 兜底：注入发生在 didFinishLaunching 之后
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!safeEnv) return;
            PCBootstrapGate();
        });
    }
}
