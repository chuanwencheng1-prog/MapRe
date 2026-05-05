//
//  PCActivationViewController.h
//  PersonalCenterUI
//
//  原生激活弹窗：专业深色风、无紫色。
//  用户输入激活码 → 调 PCAuthManager 激活 → 成功则回调继续进入主界面。
//
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface PCActivationViewController : UIViewController

/// 成功激活后回调，外层在此 present 主界面。
@property (nonatomic, copy, nullable) void (^onActivated)(void);

@end

NS_ASSUME_NONNULL_END
