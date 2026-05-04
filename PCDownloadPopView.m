//
//  PCDownloadPopView.m
//  PersonalCenterUI
//

#import "PCDownloadPopView.h"
#import <QuartzCore/QuartzCore.h>

@interface PCDownloadPopView ()
@property (nonatomic, strong) UIView              *mask;        // .download-mask
@property (nonatomic, strong) UIView              *pop;         // .download-pop-center
@property (nonatomic, strong) UILabel             *titleLabel;  // #popTitle
@property (nonatomic, strong) UIButton            *closeBtn;    // .pop-close
@property (nonatomic, strong) UIView              *progressTrack; // .progress-wrap (bg)
@property (nonatomic, strong) UIView              *progressFill;  // .progress-fill (container)
@property (nonatomic, strong) CAGradientLayer     *progressGradient; // 渐变填充
@property (nonatomic, strong) UILabel             *tipLabel;      // #progressTip
@property (nonatomic, strong) UILabel             *numLabel;      // #progressNum
@property (nonatomic, assign) CGFloat              fillMaxWidth;
@end

@implementation PCDownloadPopView

// 颜色工具
static inline UIColor *HEX(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF)/255.0
                           green:((rgb >>  8) & 0xFF)/255.0
                            blue:( rgb        & 0xFF)/255.0
                           alpha:1.0];
}

- (instancetype)init {
    if ((self = [super init])) {
        self.hidden = YES;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;

    // 半透明遮罩
    self.mask = [[UIView alloc] init];
    self.mask.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
    [self addSubview:self.mask];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismiss)];
    [self.mask addGestureRecognizer:tap];

    // 弹窗主体
    self.pop = [[UIView alloc] init];
    self.pop.backgroundColor = [UIColor whiteColor];
    self.pop.layer.cornerRadius  = 20.0;
    self.pop.layer.masksToBounds = NO;
    self.pop.layer.shadowColor   = [UIColor blackColor].CGColor;
    self.pop.layer.shadowOpacity = 0.15;
    self.pop.layer.shadowRadius  = 20.0;     // 对应 blur 40 的视觉近似（iOS 乘以 0.5）
    self.pop.layer.shadowOffset  = CGSizeMake(0, 8);
    [self addSubview:self.pop];

    // 标题
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"正在处理";
    self.titleLabel.textColor = HEX(0x222222);
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.pop addSubview:self.titleLabel];

    // 关闭按钮
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeBtn.backgroundColor = HEX(0xEEEEEE);
    self.closeBtn.layer.cornerRadius = 13;   // 26/2
    [self.closeBtn setTitle:@"×" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:HEX(0x666666) forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.closeBtn addTarget:self action:@selector(dismiss)
            forControlEvents:UIControlEventTouchUpInside];
    [self.pop addSubview:self.closeBtn];

    // 进度条轨道
    self.progressTrack = [[UIView alloc] init];
    self.progressTrack.backgroundColor = HEX(0xE9ECEF);
    self.progressTrack.layer.cornerRadius  = 6.0; // 12/2
    self.progressTrack.layer.masksToBounds = YES;
    [self.pop addSubview:self.progressTrack];

    // 进度条填充容器 (宽度动态)
    self.progressFill = [[UIView alloc] init];
    self.progressFill.layer.cornerRadius  = 6.0;
    self.progressFill.layer.masksToBounds = YES;
    self.progressFill.backgroundColor = HEX(0x00B96B);
    [self.progressTrack addSubview:self.progressFill];

    // 渐变填充
    self.progressGradient = [CAGradientLayer layer];
    self.progressGradient.colors = @[ (id)HEX(0x00B96B).CGColor,
                                      (id)HEX(0x23C97C).CGColor ];
    self.progressGradient.startPoint = CGPointMake(0, 0.5);
    self.progressGradient.endPoint   = CGPointMake(1, 0.5);
    [self.progressFill.layer addSublayer:self.progressGradient];

    // 进度文字（左：tip；右：百分比）
    self.tipLabel = [[UILabel alloc] init];
    self.tipLabel.text = @"准备初始化...";
    self.tipLabel.textColor = HEX(0x666666);
    self.tipLabel.font = [UIFont systemFontOfSize:13];
    [self.pop addSubview:self.tipLabel];

    self.numLabel = [[UILabel alloc] init];
    self.numLabel.text = @"0%";
    self.numLabel.textColor = HEX(0x666666);
    self.numLabel.font = [UIFont systemFontOfSize:13];
    self.numLabel.textAlignment = NSTextAlignmentRight;
    [self.pop addSubview:self.numLabel];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.mask.frame = self.bounds;

    CGFloat popW = 320;
    CGFloat padding = 24;
    CGFloat popX = (self.bounds.size.width  - popW) / 2.0;

    // 标题栏
    CGFloat titleY = padding;
    CGFloat titleH = 24;
    // 关闭按钮
    CGFloat closeWH = 26;
    CGFloat closeX  = popW - padding - closeWH;
    CGFloat closeY  = padding - 1;

    // 进度条
    CGFloat barTopGap = 18;
    CGFloat barY = titleY + titleH + barTopGap - 6; // 贴近 wy.html 间距
    CGFloat barH = 12;
    CGFloat barX = padding;
    CGFloat barW = popW - padding * 2;

    // 文字行
    CGFloat textY = barY + barH + 12;
    CGFloat textH = 18;

    CGFloat popH = textY + textH + padding;
    CGFloat popY = (self.bounds.size.height - popH) / 2.0;

    self.pop.frame = CGRectMake(popX, popY, popW, popH);

    self.titleLabel.frame = CGRectMake(padding, titleY, popW - padding * 2 - closeWH - 8, titleH);
    self.closeBtn.frame   = CGRectMake(closeX, closeY, closeWH, closeWH);

    self.progressTrack.frame = CGRectMake(barX, barY, barW, barH);
    self.fillMaxWidth = barW;

    // 保持当前百分比宽度
    CGFloat curW = self.progressFill.frame.size.width;
    self.progressFill.frame = CGRectMake(0, 0, MIN(curW, barW), barH);
    self.progressGradient.frame = CGRectMake(0, 0, barW, barH);

    CGFloat halfW = (popW - padding * 2) / 2.0;
    self.tipLabel.frame = CGRectMake(barX, textY, halfW * 2 - 40, textH);
    self.numLabel.frame = CGRectMake(barX + barW - 40, textY, 40, textH);
}

#pragma mark - API

- (void)showInView:(UIView *)parent title:(NSString *)title {
    if (!parent) return;
    self.frame = parent.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:self];
    self.hidden = NO;

    self.titleLabel.text = title.length ? title : @"正在处理";
    [self updateProgress:0.0 tip:@"准备初始化..."];

    // 弹出动画：对应 @keyframes popFade
    self.pop.alpha = 0;
    CGAffineTransform origin = CGAffineTransformMakeTranslation(0, -10);
    self.pop.transform = origin;
    [UIView animateWithDuration:0.3 animations:^{
        self.pop.alpha = 1.0;
        self.pop.transform = CGAffineTransformIdentity;
    }];
}

- (void)updateProgress:(double)progress tip:(NSString *)tip {
    if (progress < 0) progress = 0;
    if (progress > 1) progress = 1;
    CGFloat w = self.fillMaxWidth * progress;
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveLinear
                     animations:^{
        CGRect f = self.progressFill.frame;
        f.size.width = w;
        self.progressFill.frame = f;
    } completion:nil];
    self.numLabel.text = [NSString stringWithFormat:@"%d%%", (int)floor(progress * 100)];

    if (tip.length) {
        self.tipLabel.text = tip;
    } else {
        // 与 wy.html 中 startProgress 阶段提示一致
        double p100 = progress * 100;
        if (p100 >= 100)      self.tipLabel.text = @"操作完成！";
        else if (p100 > 80)   self.tipLabel.text = @"最后校验中...";
        else if (p100 > 40)   self.tipLabel.text = @"拉取核心资源...";
        else                  self.tipLabel.text = @"准备初始化...";
    }
}

- (void)dismiss {
    self.hidden = YES;
    [self removeFromSuperview];
    CGRect f = self.progressFill.frame;
    f.size.width = 0;
    self.progressFill.frame = f;
    self.numLabel.text = @"0%";
    self.tipLabel.text = @"准备初始化...";
}

@end
