//
//  PCAuthPopView.m
//  PersonalCenterUI
//

#import "PCAuthPopView.h"
#import "PCAuthManager.h"
#import <QuartzCore/QuartzCore.h>

static inline UIColor *HEX(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF)/255.0
                           green:((rgb >>  8) & 0xFF)/255.0
                            blue:( rgb        & 0xFF)/255.0
                           alpha:1.0];
}

@interface PCAuthPopView () <UITextFieldDelegate>
@property (nonatomic, weak)   UIViewController *hostVC;
@property (nonatomic, copy)   void (^onAuthorized)(void);

@property (nonatomic, strong) UIView          *mask;
@property (nonatomic, strong) UIView          *pop;
@property (nonatomic, strong) UIView          *headerBar;
@property (nonatomic, strong) CAGradientLayer *headerGradient;
@property (nonatomic, strong) UILabel         *headerTitle;
@property (nonatomic, strong) UILabel         *subTitle;

@property (nonatomic, strong) UIView          *inputWrap;
@property (nonatomic, strong) UITextField     *cardField;
@property (nonatomic, strong) UIButton        *pasteBtn;

@property (nonatomic, strong) UILabel         *deviceLabel;
@property (nonatomic, strong) UIButton        *deviceCopyBtn;

@property (nonatomic, strong) UIButton        *activateBtn;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel         *statusLabel;

@property (nonatomic, strong) UILabel         *footerLabel;
@end

@implementation PCAuthPopView

- (instancetype)init {
    if ((self = [super init])) {
        self.backgroundColor = [UIColor clearColor];
        [self buildUI];
    }
    return self;
}

#pragma mark - UI

- (void)buildUI {
    self.mask = [[UIView alloc] init];
    self.mask.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    [self addSubview:self.mask];

    self.pop = [[UIView alloc] init];
    self.pop.backgroundColor = [UIColor whiteColor];
    self.pop.layer.cornerRadius = 20.0;
    self.pop.layer.masksToBounds = NO;
    self.pop.layer.shadowColor = [UIColor blackColor].CGColor;
    self.pop.layer.shadowOpacity = 0.18;
    self.pop.layer.shadowRadius = 22.0;
    self.pop.layer.shadowOffset = CGSizeMake(0, 10);
    [self addSubview:self.pop];

    // 标题栏
    self.headerBar = [[UIView alloc] init];
    self.headerBar.layer.masksToBounds = YES;
    self.headerBar.layer.cornerRadius = 20.0;
    // 只给顶部两个圆角
    self.headerBar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self.pop addSubview:self.headerBar];

    self.headerGradient = [CAGradientLayer layer];
    self.headerGradient.colors = @[(id)HEX(0x1677FF).CGColor, (id)HEX(0x0958D9).CGColor];
    self.headerGradient.startPoint = CGPointMake(0, 0);
    self.headerGradient.endPoint = CGPointMake(1, 1);
    [self.headerBar.layer addSublayer:self.headerGradient];

    self.headerTitle = [[UILabel alloc] init];
    self.headerTitle.text = @"🔐 卡密激活";
    self.headerTitle.textColor = [UIColor whiteColor];
    self.headerTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.headerTitle.textAlignment = NSTextAlignmentCenter;
    [self.headerBar addSubview:self.headerTitle];

    self.subTitle = [[UILabel alloc] init];
    self.subTitle.text = @"请粘贴购买的卡密以激活本设备";
    self.subTitle.textColor = HEX(0x666666);
    self.subTitle.font = [UIFont systemFontOfSize:12];
    self.subTitle.textAlignment = NSTextAlignmentCenter;
    self.subTitle.numberOfLines = 0;
    [self.pop addSubview:self.subTitle];

    // 输入框容器
    self.inputWrap = [[UIView alloc] init];
    self.inputWrap.backgroundColor = HEX(0xF6F8FA);
    self.inputWrap.layer.cornerRadius = 10.0;
    self.inputWrap.layer.borderWidth = 1.0;
    self.inputWrap.layer.borderColor = HEX(0xE4E7EB).CGColor;
    [self.pop addSubview:self.inputWrap];

    self.cardField = [[UITextField alloc] init];
    self.cardField.placeholder = @"输入或粘贴卡密";
    self.cardField.font = [UIFont systemFontOfSize:14];
    self.cardField.textColor = HEX(0x222222);
    self.cardField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.cardField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.cardField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.cardField.returnKeyType = UIReturnKeyGo;
    self.cardField.delegate = self;
    [self.inputWrap addSubview:self.cardField];

    self.pasteBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.pasteBtn setTitle:@"粘贴" forState:UIControlStateNormal];
    [self.pasteBtn setTitleColor:HEX(0x1677FF) forState:UIControlStateNormal];
    self.pasteBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.pasteBtn addTarget:self action:@selector(onPaste) forControlEvents:UIControlEventTouchUpInside];
    [self.inputWrap addSubview:self.pasteBtn];

    // 机器码
    self.deviceLabel = [[UILabel alloc] init];
    self.deviceLabel.font = [UIFont systemFontOfSize:11];
    self.deviceLabel.textColor = HEX(0x999999);
    self.deviceLabel.numberOfLines = 2;
    NSString *did = [[PCAuthManager sharedManager] deviceID];
    NSString *shortDid = did.length > 16 ? [NSString stringWithFormat:@"%@...%@",
                                            [did substringToIndex:8],
                                            [did substringFromIndex:did.length - 8]] : did;
    self.deviceLabel.text = [NSString stringWithFormat:@"机器码: %@", shortDid ?: @""];
    [self.pop addSubview:self.deviceLabel];

    self.deviceCopyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.deviceCopyBtn setTitle:@"复制" forState:UIControlStateNormal];
    [self.deviceCopyBtn setTitleColor:HEX(0x1677FF) forState:UIControlStateNormal];
    self.deviceCopyBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.deviceCopyBtn addTarget:self action:@selector(onCopyDeviceID) forControlEvents:UIControlEventTouchUpInside];
    [self.pop addSubview:self.deviceCopyBtn];

    // 激活按钮
    self.activateBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.activateBtn.backgroundColor = HEX(0x1677FF);
    self.activateBtn.layer.cornerRadius = 10.0;
    [self.activateBtn setTitle:@"立即激活" forState:UIControlStateNormal];
    [self.activateBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.activateBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.activateBtn addTarget:self action:@selector(onActivate) forControlEvents:UIControlEventTouchUpInside];
    [self.pop addSubview:self.activateBtn];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    [self.activateBtn addSubview:self.spinner];

    // 状态文字
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = HEX(0xE74C3C);
    self.statusLabel.numberOfLines = 2;
    [self.pop addSubview:self.statusLabel];

    // footer
    self.footerLabel = [[UILabel alloc] init];
    self.footerLabel.text = @"本设备机器码仅绑定本卡，请妥善保管卡密";
    self.footerLabel.textColor = HEX(0xBBBBBB);
    self.footerLabel.font = [UIFont systemFontOfSize:10];
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    [self.pop addSubview:self.footerLabel];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.mask.frame = self.bounds;

    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    CGFloat popW = MIN(W - 40, 340);
    CGFloat padding = 20;

    CGFloat headerH = 56;
    CGFloat subTitleH = 32;
    CGFloat inputH = 46;
    CGFloat deviceRowH = 32;
    CGFloat btnH = 46;
    CGFloat statusH = 28;
    CGFloat footerH = 18;

    CGFloat popH = headerH + 16 + subTitleH + 14 + inputH + 10 + deviceRowH + 14
                 + btnH + 6 + statusH + 8 + footerH + padding;
    CGFloat popX = (W - popW) / 2.0;
    CGFloat popY = (H - popH) / 2.0;
    self.pop.frame = CGRectMake(popX, popY, popW, popH);

    self.headerBar.frame = CGRectMake(0, 0, popW, headerH);
    self.headerGradient.frame = self.headerBar.bounds;
    self.headerTitle.frame = self.headerBar.bounds;

    CGFloat y = headerH + 16;
    self.subTitle.frame = CGRectMake(padding, y, popW - padding * 2, subTitleH);
    y += subTitleH + 14;

    self.inputWrap.frame = CGRectMake(padding, y, popW - padding * 2, inputH);
    self.cardField.frame = CGRectMake(14, 0, self.inputWrap.bounds.size.width - 14 - 64, inputH);
    self.pasteBtn.frame  = CGRectMake(self.inputWrap.bounds.size.width - 64, 0, 54, inputH);
    y += inputH + 10;

    self.deviceLabel.frame = CGRectMake(padding, y, popW - padding * 2 - 48, deviceRowH);
    self.deviceCopyBtn.frame = CGRectMake(popW - padding - 48, y, 48, deviceRowH);
    y += deviceRowH + 14;

    self.activateBtn.frame = CGRectMake(padding, y, popW - padding * 2, btnH);
    self.spinner.frame = CGRectMake(self.activateBtn.bounds.size.width/2 - 50, (btnH-20)/2.0, 20, 20);
    y += btnH + 6;

    self.statusLabel.frame = CGRectMake(padding, y, popW - padding * 2, statusH);
    y += statusH + 8;

    self.footerLabel.frame = CGRectMake(padding, y, popW - padding * 2, footerH);
}

#pragma mark - Actions

- (void)onPaste {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (s.length) {
        self.cardField.text = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self flashStatus:@"已粘贴剪贴板内容" color:HEX(0x00B96B)];
    } else {
        [self flashStatus:@"剪贴板为空" color:HEX(0xE74C3C)];
    }
}

- (void)onCopyDeviceID {
    NSString *did = [[PCAuthManager sharedManager] deviceID];
    [UIPasteboard generalPasteboard].string = did ?: @"";
    [self flashStatus:@"机器码已复制" color:HEX(0x00B96B)];
}

- (void)onActivate {
    NSString *card = [self.cardField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!card.length) {
        [self flashStatus:@"请输入卡密" color:HEX(0xE74C3C)];
        return;
    }
    [self.cardField resignFirstResponder];
    [self setLoading:YES];
    __weak typeof(self) ws = self;
    [[PCAuthManager sharedManager] activateWithCard:card completion:^(PCAuthStatus status, NSTimeInterval expiresAt, NSString * _Nullable message) {
        __strong typeof(ws) ss = ws;
        if (!ss) return;
        [ss setLoading:NO];
        if (status == PCAuthStatusValid) {
            NSString *leftTip = [ss humanLeftTime:expiresAt];
            [ss flashStatus:[NSString stringWithFormat:@"✓ 激活成功，%@", leftTip] color:HEX(0x00B96B)];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [ss dismissAndContinue];
            });
        } else {
            NSString *tip = message.length ? message : @"激活失败";
            if (status == PCAuthStatusSignatureBad) tip = @"签名校验失败，请检查服务器";
            if (status == PCAuthStatusDeviceMismatch) tip = @"卡密已绑定其它设备";
            if (status == PCAuthStatusExpired) tip = @"卡密已过期";
            if (status == PCAuthStatusNetwork) tip = [NSString stringWithFormat:@"网络异常：%@", message ?: @""];
            [ss flashStatus:tip color:HEX(0xE74C3C)];
        }
    }];
}

- (void)setLoading:(BOOL)loading {
    self.activateBtn.enabled = !loading;
    self.activateBtn.alpha = loading ? 0.7 : 1.0;
    if (loading) {
        [self.spinner startAnimating];
        [self.activateBtn setTitle:@"  校验中..." forState:UIControlStateNormal];
    } else {
        [self.spinner stopAnimating];
        [self.activateBtn setTitle:@"立即激活" forState:UIControlStateNormal];
    }
}

- (void)flashStatus:(NSString *)msg color:(UIColor *)color {
    self.statusLabel.textColor = color;
    self.statusLabel.text = msg;
}

- (NSString *)humanLeftTime:(NSTimeInterval)expiresAt {
    NSTimeInterval left = expiresAt - [[NSDate date] timeIntervalSince1970];
    if (left <= 0) return @"已到期";
    long d = (long)(left / 86400);
    long h = (long)((left - d * 86400) / 3600);
    long m = (long)((left - d * 86400 - h * 3600) / 60);
    if (d > 0) return [NSString stringWithFormat:@"剩余 %ld 天 %ld 小时", d, h];
    if (h > 0) return [NSString stringWithFormat:@"剩余 %ld 小时 %ld 分钟", h, m];
    return [NSString stringWithFormat:@"剩余 %ld 分钟", m];
}

#pragma mark - Present / Dismiss

- (void)presentFromVC:(UIViewController *)parentVC onAuthorized:(void (^)(void))onAuthorized {
    self.hostVC = parentVC;
    self.onAuthorized = onAuthorized;
    UIView *container = parentVC.view;
    self.frame = container.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:self];

    // 入场动画
    self.pop.alpha = 0;
    self.pop.transform = CGAffineTransformMakeScale(0.9, 0.9);
    self.mask.alpha = 0;
    [UIView animateWithDuration:0.25 animations:^{
        self.mask.alpha = 1;
        self.pop.alpha = 1;
        self.pop.transform = CGAffineTransformIdentity;
    }];

    // 若本地已有有效授权 → 直接走心跳校验，成功就放行
    if ([[PCAuthManager sharedManager] isLocallyAuthorized]) {
        [self setLoading:YES];
        [self flashStatus:@"正在校验已有授权..." color:HEX(0x666666)];
        __weak typeof(self) ws = self;
        [[PCAuthManager sharedManager] verifyWithCompletion:^(PCAuthStatus status, NSTimeInterval expiresAt, NSString * _Nullable message) {
            __strong typeof(ws) ss = ws; if (!ss) return;
            [ss setLoading:NO];
            if (status == PCAuthStatusValid) {
                [ss flashStatus:[NSString stringWithFormat:@"✓ 已授权，%@", [ss humanLeftTime:expiresAt]] color:HEX(0x00B96B)];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [ss dismissAndContinue];
                });
            } else if (status == PCAuthStatusNetwork) {
                // 网络异常 + 本地仍然有效 → 仍放行（离线兜底）
                [ss flashStatus:@"网络异常，使用本地缓存放行" color:HEX(0xFF9800)];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [ss dismissAndContinue];
                });
            } else {
                // 服务器说不行，清缓存要求重激活
                [[PCAuthManager sharedManager] clearCache];
                NSString *tip = message ?: @"授权失效，请重新激活";
                [ss flashStatus:tip color:HEX(0xE74C3C)];
            }
        }];
    }
}

- (void)dismissAndContinue {
    void (^cb)(void) = self.onAuthorized;
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
    } completion:^(BOOL f) {
        [self removeFromSuperview];
        if (cb) cb();
    }];
}

#pragma mark - TextField

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self onActivate];
    return YES;
}

@end
