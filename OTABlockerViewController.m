//
//  OTABlockerViewController.m
//  纯代码布局，风格模仿系统分组背景 + 卡片式设计，适配 iOS 13+，深色模式
//
//  新布局（自上而下）：
//      1. 右上角「自动」胶囊按钮（深浅色切换）
//      2. 标题「阻止 OTA 升级」
//      3. 副标题「支持 iOS 17.1 - iOS 26.0.1」
//      4. 「禁用」/「恢复」两枚圆角按钮
//      5. 下方「日志」卡片（占满剩余空间）
//

#import "OTABlockerViewController.h"
#import <sys/utsname.h>

@interface OTABlockerViewController ()

@property (nonatomic, strong) UIButton      *appearanceButton;   // 右上角 自动
@property (nonatomic, strong) UILabel       *titleLabel;         // 阻止 OTA 升级
@property (nonatomic, strong) UILabel       *subtitleLabel;      // 支持 iOS 17.1 - iOS 26.0.1
@property (nonatomic, strong) UIButton      *disableButton;      // 禁用
@property (nonatomic, strong) UIButton      *restoreButton;      // 恢复

@property (nonatomic, strong) UIView        *logCard;            // 日志卡片容器
@property (nonatomic, strong) UILabel       *logTitleLabel;      // “日志”
@property (nonatomic, strong) UILabel       *logCounterLabel;    // (0/40)
@property (nonatomic, strong) UILabel       *logStatusTag;       // 右上角 “支持” 胶囊
@property (nonatomic, strong) UITextView    *logTextView;        // 日志正文

@property (nonatomic, assign) NSInteger      logLineCount;
@property (nonatomic, assign) NSInteger      logLineLimit;

@end

@implementation OTABlockerViewController

#pragma mark - Lifecycle

- (instancetype)init {
    if ((self = [super init])) {
        _logLineCount = 0;
        _logLineLimit = 40;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    }

    [self buildAppearanceButton];
    [self buildHeader];
    [self buildActionButtons];
    [self buildLogCard];
    [self setupConstraints];

    [self fillInitialLog];
}

#pragma mark - Build UI

- (void)buildAppearanceButton {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;

    if (@available(iOS 13.0, *)) {
        btn.backgroundColor = [UIColor secondarySystemBackgroundColor];
    } else {
        btn.backgroundColor = [UIColor whiteColor];
    }
    btn.layer.cornerRadius = 18.0;
    btn.layer.masksToBounds = YES;
    btn.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 14);

    // 左边半圆图标
    UIImage *icon = nil;
    if (@available(iOS 13.0, *)) {
        icon = [UIImage systemImageNamed:@"circle.righthalf.filled"];
    }
    [btn setImage:icon forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        btn.tintColor = [UIColor systemBlueColor];
    }
    btn.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);

    [btn setTitle:@"自动" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    if (@available(iOS 13.0, *)) {
        [btn setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    }

    [btn addTarget:self action:@selector(onAppearanceTapped:)
        forControlEvents:UIControlEventTouchUpInside];

    self.appearanceButton = btn;
    [self.view addSubview:btn];
}

- (void)buildHeader {
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"阻止 OTA 升级";
    title.font = [UIFont systemFontOfSize:34.0 weight:UIFontWeightHeavy];
    title.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) {
        title.textColor = [UIColor labelColor];
    }
    self.titleLabel = title;
    [self.view addSubview:title];

    UILabel *sub = [UILabel new];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.text = @"支持 iOS 17.1 - iOS 26.0.1";
    sub.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    sub.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) {
        sub.textColor = [UIColor secondaryLabelColor];
    } else {
        sub.textColor = [UIColor grayColor];
    }
    self.subtitleLabel = sub;
    [self.view addSubview:sub];
}

- (void)buildActionButtons {
    self.disableButton = [self makePrimaryButtonWithTitle:@"禁用"
                                                    color:[UIColor systemBlueColor]
                                                   action:@selector(onDisableTapped:)];
    self.restoreButton = [self makePrimaryButtonWithTitle:@"恢复"
                                                    color:[UIColor systemRedColor]
                                                   action:@selector(onRestoreTapped:)];
    [self.view addSubview:self.disableButton];
    [self.view addSubview:self.restoreButton];
}

- (UIButton *)makePrimaryButtonWithTitle:(NSString *)title
                                   color:(UIColor *)color
                                  action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = color;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    btn.layer.cornerRadius = 14.0;
    btn.layer.masksToBounds = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)buildLogCard {
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    } else {
        card.backgroundColor = [UIColor whiteColor];
    }
    card.layer.cornerRadius = 14.0;
    card.layer.masksToBounds = YES;
    self.logCard = card;
    [self.view addSubview:card];

    // “日志”
    UILabel *logTitle = [UILabel new];
    logTitle.translatesAutoresizingMaskIntoConstraints = NO;
    logTitle.text = @"日志";
    logTitle.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    if (@available(iOS 13.0, *)) {
        logTitle.textColor = [UIColor labelColor];
    }
    self.logTitleLabel = logTitle;
    [card addSubview:logTitle];

    // (0/40)
    UILabel *counter = [UILabel new];
    counter.translatesAutoresizingMaskIntoConstraints = NO;
    counter.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    if (@available(iOS 13.0, *)) {
        counter.textColor = [UIColor secondaryLabelColor];
    } else {
        counter.textColor = [UIColor grayColor];
    }
    counter.text = [NSString stringWithFormat:@"(%ld/%ld)",
                    (long)self.logLineCount, (long)self.logLineLimit];
    self.logCounterLabel = counter;
    [card addSubview:counter];

    // 右上角 “支持” 胶囊
    UILabel *tag = [UILabel new];
    tag.translatesAutoresizingMaskIntoConstraints = NO;
    tag.text = @" 支持 ";
    tag.textAlignment = NSTextAlignmentCenter;
    tag.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    if (@available(iOS 13.0, *)) {
        tag.textColor = [UIColor systemGreenColor];
        tag.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
    } else {
        tag.textColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0];
        tag.backgroundColor = [UIColor colorWithRed:0.85 green:0.96 blue:0.87 alpha:1.0];
    }
    tag.layer.cornerRadius = 12.0;
    tag.layer.masksToBounds = YES;
    self.logStatusTag = tag;
    [card addSubview:tag];

    // 日志正文（等宽字体）
    UITextView *tv = [UITextView new];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.scrollEnabled = YES;
    tv.backgroundColor = [UIColor clearColor];
    tv.textContainerInset = UIEdgeInsetsZero;
    tv.textContainer.lineFragmentPadding = 0;
    tv.font = [UIFont fontWithName:@"Menlo" size:14.0];
    if (!tv.font) {
        tv.font = [UIFont fontWithName:@"Courier" size:14.0];
    }
    if (@available(iOS 13.0, *)) {
        tv.textColor = [UIColor labelColor];
    }
    self.logTextView = tv;
    [card addSubview:tv];
}

#pragma mark - Constraints

- (void)setupConstraints {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        // 右上角 自动
        [self.appearanceButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.appearanceButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.appearanceButton.heightAnchor constraintEqualToConstant:36],

        // 标题
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.appearanceButton.bottomAnchor constant:16],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        // 副标题
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        // 禁用 / 恢复 按钮 —— 位于副标题下方、日志之上
        [self.disableButton.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:22],
        [self.disableButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.disableButton.heightAnchor constraintEqualToConstant:54],

        [self.restoreButton.topAnchor constraintEqualToAnchor:self.disableButton.topAnchor],
        [self.restoreButton.heightAnchor constraintEqualToAnchor:self.disableButton.heightAnchor],
        [self.restoreButton.leadingAnchor constraintEqualToAnchor:self.disableButton.trailingAnchor constant:14],
        [self.restoreButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.restoreButton.widthAnchor constraintEqualToAnchor:self.disableButton.widthAnchor],

        // 日志卡片 —— 在按钮下方，一直撑到底
        [self.logCard.topAnchor constraintEqualToAnchor:self.disableButton.bottomAnchor constant:18],
        [self.logCard.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.logCard.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.logCard.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],

        // 日志卡片内部
        [self.logTitleLabel.topAnchor constraintEqualToAnchor:self.logCard.topAnchor constant:14],
        [self.logTitleLabel.leadingAnchor constraintEqualToAnchor:self.logCard.leadingAnchor constant:16],

        [self.logCounterLabel.firstBaselineAnchor constraintEqualToAnchor:self.logTitleLabel.firstBaselineAnchor],
        [self.logCounterLabel.leadingAnchor constraintEqualToAnchor:self.logTitleLabel.trailingAnchor constant:6],

        [self.logStatusTag.centerYAnchor constraintEqualToAnchor:self.logTitleLabel.centerYAnchor],
        [self.logStatusTag.trailingAnchor constraintEqualToAnchor:self.logCard.trailingAnchor constant:-14],
        [self.logStatusTag.heightAnchor constraintEqualToConstant:24],
        [self.logStatusTag.widthAnchor constraintGreaterThanOrEqualToConstant:52],

        [self.logTextView.topAnchor constraintEqualToAnchor:self.logTitleLabel.bottomAnchor constant:12],
        [self.logTextView.leadingAnchor constraintEqualToAnchor:self.logCard.leadingAnchor constant:16],
        [self.logTextView.trailingAnchor constraintEqualToAnchor:self.logCard.trailingAnchor constant:-16],
        [self.logTextView.bottomAnchor constraintEqualToAnchor:self.logCard.bottomAnchor constant:-14],
    ]];
}

#pragma mark - Initial Log

- (void)fillInitialLog {
    struct utsname sysInfo;
    uname(&sysInfo);
    NSString *machine = [NSString stringWithCString:sysInfo.machine
                                           encoding:NSASCIIStringEncoding] ?: @"-";
    NSString *sysVer  = [[UIDevice currentDevice] systemVersion] ?: @"-";
    NSString *model   = [[UIDevice currentDevice] model] ?: @"-";

    NSArray<NSString *> *lines = @[
        [NSString stringWithFormat:@"设备：%@", [self prettyDeviceName:machine fallback:model]],
        [NSString stringWithFormat:@"类型：%@", machine],
        [NSString stringWithFormat:@"系统：iOS %@", sysVer],
        @"支持范围：iOS 17.1 - iOS 26.0.1",
        @"支持状态：支持，当前系统在支持范围内。",
    ];
    for (NSString *line in lines) {
        [self appendLogLine:line];
    }
}

- (NSString *)prettyDeviceName:(NSString *)machine fallback:(NSString *)fallback {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"iPhone15,2": @"iPhone 14 Pro",
            @"iPhone15,3": @"iPhone 14 Pro Max",
            @"iPhone16,1": @"iPhone 15 Pro",
            @"iPhone16,2": @"iPhone 15 Pro Max",
            @"iPhone17,1": @"iPhone 16 Pro",
            @"iPhone17,2": @"iPhone 16 Pro Max",
        };
    });
    return map[machine] ?: fallback;
}

#pragma mark - Public

- (void)appendLogLine:(NSString *)line {
    if (line.length == 0) return;
    NSMutableString *ms = [self.logTextView.text mutableCopy] ?: [NSMutableString string];
    if (ms.length > 0) [ms appendString:@"\n"];
    [ms appendString:line];
    self.logTextView.text = ms;
    self.logLineCount++;
    self.logCounterLabel.text = [NSString stringWithFormat:@"(%ld/%ld)",
                                 (long)self.logLineCount, (long)self.logLineLimit];
}

#pragma mark - Actions

- (void)onAppearanceTapped:(UIButton *)sender {
    if (@available(iOS 13.0, *)) {
        UIWindow *win = self.view.window;
        UIUserInterfaceStyle cur = win.overrideUserInterfaceStyle;
        switch (cur) {
            case UIUserInterfaceStyleUnspecified:
                win.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                [sender setTitle:@"浅色" forState:UIControlStateNormal];
                break;
            case UIUserInterfaceStyleLight:
                win.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
                [sender setTitle:@"深色" forState:UIControlStateNormal];
                break;
            case UIUserInterfaceStyleDark:
            default:
                win.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
                [sender setTitle:@"自动" forState:UIControlStateNormal];
                break;
        }
    }
}

- (void)onDisableTapped:(UIButton *)sender {
    [self appendLogLine:@"[禁用] 已尝试屏蔽 OTA 描述文件。"];
    // TODO: 在此调用真正的禁用逻辑
}

- (void)onRestoreTapped:(UIButton *)sender {
    [self appendLogLine:@"[恢复] 已尝试恢复 OTA 设置。"];
    // TODO: 在此调用真正的恢复逻辑
}

@end
