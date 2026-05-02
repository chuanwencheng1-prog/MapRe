//
//  OTABlockerViewController.h
//  dylib 注入到宿主 App 后，在第一屏显示的 “阻止 OTA 升级” 界面
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OTABlockerViewController : UIViewController

// 外部可通过该方法向日志区域追加一行
- (void)appendLogLine:(NSString *)line;

@end

NS_ASSUME_NONNULL_END
