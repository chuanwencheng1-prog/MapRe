//
//  PCAuthPopView.h
//  PersonalCenterUI
//
//  启动前的卡密激活弹窗：
//    - 居中 320pt 圆角 20 风格（与 PCDownloadPopView 一致）
//    - 顶部渐变标题栏
//    - 卡密输入框 + 粘贴按钮 + 机器码（点击复制）
//    - 激活按钮 / 校验中状态
//    - 激活成功回调由调用方处理：继续 present 主 VC
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PCAuthPopView : UIView

/// 显示在给定的父 VC 上（全屏覆盖，不可下穿）
/// @param parentVC 承载控制器
/// @param onAuthorized 授权成功回调（主线程）
- (void)presentFromVC:(UIViewController *)parentVC
         onAuthorized:(void(^)(void))onAuthorized;

@end

NS_ASSUME_NONNULL_END
