//
//  PCDownloadPopView.h
//  PersonalCenterUI
//
//  对应 wy.html 中 .download-mask / .download-pop-center 的居中下载进度弹窗
//  尺寸 320pt 宽，圆角 20，阴影 0 8 40 rgba(0,0,0,0.15)
//  进度条 12pt 高、渐变 #00b96b → #23c97c
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PCDownloadPopView : UIView

/// 在指定父视图上弹出
/// @param parent 父视图（一般是 VC.view）
/// @param title  弹窗标题（如："正在执行：全部订单"）
- (void)showInView:(UIView *)parent title:(NSString *)title;

/// 更新进度（0.0 ~ 1.0）+ 辅助提示文案
- (void)updateProgress:(double)progress tip:(nullable NSString *)tip;

/// 隐藏 & 重置
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
