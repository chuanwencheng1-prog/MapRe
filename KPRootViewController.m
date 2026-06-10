#import "KPRootViewController.h"

@interface KPRootViewController () <UITextFieldDelegate>

// Header Card
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UITextField *activateInput;
@property (nonatomic, strong) UIButton *activateBtn;
@property (nonatomic, strong) UILabel *expireTips;

// Main Content
@property (nonatomic, strong) UIView *mainContent;
@property (nonatomic, strong) UIButton *readBtn;
@property (nonatomic, strong) UIButton *resetBtn;
@property (nonatomic, strong) UIButton *downBtn1;
@property (nonatomic, strong) UIButton *downBtn2;
@property (nonatomic, strong) UIButton *downBtn3;
@property (nonatomic, strong) UIButton *downBtn4;
@property (nonatomic, strong) UIButton *downBtn5;
@property (nonatomic, strong) UIButton *downBtn6;
@property (nonatomic, strong) UIButton *startBtn;

// Log Container
@property (nonatomic, strong) UIView *logContainer;
@property (nonatomic, strong) UILabel *logTitle;
@property (nonatomic, strong) UIView *blinkLine;
@property (nonatomic, strong) UIScrollView *logScrollView;
@property (nonatomic, strong) UIView *logContentView;

// State
@property (nonatomic, assign) BOOL readDone;
@property (nonatomic, assign) BOOL initDone;
@property (nonatomic, strong) NSString *correctKey;

@end

@implementation KPRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.correctKey = @"1";
    self.readDone = NO;
    self.initDone = NO;
    
    self.view.backgroundColor = [UIColor colorWithRed:0.949 green:0.953 blue:0.969 alpha:1.0]; // #f2f3f7
    
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:scrollView];
    
    UIView *contentWrapper = [[UIView alloc] init];
    contentWrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentWrapper];
    
    if (@available(iOS 11.0, *)) {
        [NSLayoutConstraint activateConstraints:@[
            [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [scrollView.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor],
            [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        ]];
    }
    
    [NSLayoutConstraint activateConstraints:@[
        [contentWrapper.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [contentWrapper.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [contentWrapper.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [contentWrapper.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [contentWrapper.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
    ]];
    
    [self setupHeaderCard:contentWrapper];
    [self setupMainContent:contentWrapper];
    [self setupLogContainer:contentWrapper];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.headerCard.topAnchor constraintEqualToAnchor:contentWrapper.topAnchor constant:20],
        [self.headerCard.leadingAnchor constraintEqualToAnchor:contentWrapper.leadingAnchor constant:16],
        [self.headerCard.trailingAnchor constraintEqualToAnchor:contentWrapper.trailingAnchor constant:-16],
        
        [self.mainContent.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:20],
        [self.mainContent.leadingAnchor constraintEqualToAnchor:contentWrapper.leadingAnchor constant:16],
        [self.mainContent.trailingAnchor constraintEqualToAnchor:contentWrapper.trailingAnchor constant:-16],
        
        [self.logContainer.topAnchor constraintEqualToAnchor:self.mainContent.bottomAnchor constant:20],
        [self.logContainer.leadingAnchor constraintEqualToAnchor:contentWrapper.leadingAnchor constant:16],
        [self.logContainer.trailingAnchor constraintEqualToAnchor:contentWrapper.trailingAnchor constant:-16],
        [self.logContainer.bottomAnchor constraintEqualToAnchor:contentWrapper.bottomAnchor constant:-20],
    ]];
    
    // Entry animations
    [self performEntryAnimations];
    
    // Initial log
    [self addLog:@"面板初始化完成，请先输入卡密激活"];
}

#pragma mark - Header Card

- (void)setupHeaderCard:(UIView *)parent {
    self.headerCard = [[UIView alloc] init];
    self.headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerCard.backgroundColor = [UIColor whiteColor];
    self.headerCard.layer.cornerRadius = 18;
    self.headerCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.headerCard.layer.shadowOpacity = 0.06;
    self.headerCard.layer.shadowOffset = CGSizeMake(0, 4);
    self.headerCard.layer.shadowRadius = 16;
    [parent addSubview:self.headerCard];
    
    // Activate input
    self.activateInput = [[UITextField alloc] init];
    self.activateInput.translatesAutoresizingMaskIntoConstraints = NO;
    self.activateInput.placeholder = @"请输入卡密";
    self.activateInput.font = [UIFont systemFontOfSize:14];
    self.activateInput.layer.cornerRadius = 12;
    self.activateInput.layer.borderWidth = 1;
    self.activateInput.layer.borderColor = [UIColor colorWithRed:0.867 green:0.867 blue:0.867 alpha:1.0].CGColor; // #ddd
    self.activateInput.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 44)];
    self.activateInput.leftViewMode = UITextFieldViewModeAlways;
    self.activateInput.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 44)];
    self.activateInput.rightViewMode = UITextFieldViewModeAlways;
    self.activateInput.delegate = self;
    [self.headerCard addSubview:self.activateInput];
    
    // Activate button
    self.activateBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.activateBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activateBtn setTitle:@"激活" forState:UIControlStateNormal];
    [self.activateBtn setTitleColor:[UIColor colorWithRed:0.204 green:0.780 blue:0.349 alpha:1.0] forState:UIControlStateNormal]; // #34c759
    self.activateBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    self.activateBtn.backgroundColor = [UIColor colorWithRed:0.941 green:0.969 blue:0.941 alpha:1.0]; // #f0f7f0
    self.activateBtn.layer.cornerRadius = 12;
    [self.activateBtn addTarget:self action:@selector(activateTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerCard addSubview:self.activateBtn];
    
    // Expire tips
    self.expireTips = [[UILabel alloc] init];
    self.expireTips.translatesAutoresizingMaskIntoConstraints = NO;
    self.expireTips.text = @"卡密到期时间：2026-12-31";
    self.expireTips.font = [UIFont systemFontOfSize:12];
    self.expireTips.textColor = [UIColor blackColor];
    self.expireTips.textAlignment = NSTextAlignmentCenter;
    self.expireTips.alpha = 0;
    self.expireTips.hidden = YES;
    [self.headerCard addSubview:self.expireTips];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.activateInput.topAnchor constraintEqualToAnchor:self.headerCard.topAnchor constant:20],
        [self.activateInput.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:20],
        [self.activateInput.heightAnchor constraintEqualToConstant:44],
        
        [self.activateBtn.topAnchor constraintEqualToAnchor:self.headerCard.topAnchor constant:20],
        [self.activateBtn.leadingAnchor constraintEqualToAnchor:self.activateInput.trailingAnchor constant:10],
        [self.activateBtn.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-20],
        [self.activateBtn.widthAnchor constraintEqualToConstant:80],
        [self.activateBtn.heightAnchor constraintEqualToConstant:44],
        
        [self.expireTips.topAnchor constraintEqualToAnchor:self.activateInput.bottomAnchor constant:8],
        [self.expireTips.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:20],
        [self.expireTips.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-20],
        [self.expireTips.bottomAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:-20],
    ]];
    
    [self.headerCard.heightAnchor constraintGreaterThanOrEqualToConstant:90].active = YES;
}

#pragma mark - Main Content

- (void)setupMainContent:(UIView *)parent {
    self.mainContent = [[UIView alloc] init];
    self.mainContent.translatesAutoresizingMaskIntoConstraints = NO;
    self.mainContent.backgroundColor = [UIColor whiteColor];
    self.mainContent.layer.cornerRadius = 18;
    self.mainContent.layer.shadowColor = [UIColor blackColor].CGColor;
    self.mainContent.layer.shadowOpacity = 0.06;
    self.mainContent.layer.shadowOffset = CGSizeMake(0, 4);
    self.mainContent.layer.shadowRadius = 16;
    [parent addSubview:self.mainContent];
    
    // Button group (read + init)
    UIView *btnGroup = [[UIView alloc] init];
    btnGroup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainContent addSubview:btnGroup];
    
    self.readBtn = [self createIOSButton:@"启动内核读写"];
    self.resetBtn = [self createIOSButton:@"初始化内核"];
    [btnGroup addSubview:self.readBtn];
    [btnGroup addSubview:self.resetBtn];
    
    [NSLayoutConstraint activateConstraints:@[
        [btnGroup.topAnchor constraintEqualToAnchor:self.mainContent.topAnchor constant:20],
        [btnGroup.leadingAnchor constraintEqualToAnchor:self.mainContent.leadingAnchor constant:20],
        [btnGroup.trailingAnchor constraintEqualToAnchor:self.mainContent.trailingAnchor constant:-20],
        [btnGroup.heightAnchor constraintEqualToConstant:48],
        
        [self.readBtn.topAnchor constraintEqualToAnchor:btnGroup.topAnchor],
        [self.readBtn.bottomAnchor constraintEqualToAnchor:btnGroup.bottomAnchor],
        [self.readBtn.leadingAnchor constraintEqualToAnchor:btnGroup.leadingAnchor],
        
        [self.resetBtn.topAnchor constraintEqualToAnchor:btnGroup.topAnchor],
        [self.resetBtn.bottomAnchor constraintEqualToAnchor:btnGroup.bottomAnchor],
        [self.resetBtn.leadingAnchor constraintEqualToAnchor:self.readBtn.trailingAnchor constant:12],
        [self.resetBtn.trailingAnchor constraintEqualToAnchor:btnGroup.trailingAnchor],
        [self.resetBtn.widthAnchor constraintEqualToAnchor:self.readBtn.widthAnchor],
    ]];
    
    [self.readBtn addTarget:self action:@selector(readBtnTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.resetBtn addTarget:self action:@selector(resetBtnTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Content button group - row 1
    UIView *contentRow1 = [[UIView alloc] init];
    contentRow1.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainContent addSubview:contentRow1];
    
    self.downBtn1 = [self createContentButton:@"测试测试(测试)"];
    self.downBtn2 = [self createContentButton:@"测试测试(测试)"];
    self.downBtn3 = [self createContentButton:@"测试测试(测试)"];
    [contentRow1 addSubview:self.downBtn1];
    [contentRow1 addSubview:self.downBtn2];
    [contentRow1 addSubview:self.downBtn3];
    
    [NSLayoutConstraint activateConstraints:@[
        [contentRow1.topAnchor constraintEqualToAnchor:btnGroup.bottomAnchor constant:24],
        [contentRow1.leadingAnchor constraintEqualToAnchor:self.mainContent.leadingAnchor constant:10],
        [contentRow1.trailingAnchor constraintEqualToAnchor:self.mainContent.trailingAnchor constant:-10],
        [contentRow1.heightAnchor constraintEqualToConstant:44],
        
        [self.downBtn1.topAnchor constraintEqualToAnchor:contentRow1.topAnchor],
        [self.downBtn1.bottomAnchor constraintEqualToAnchor:contentRow1.bottomAnchor],
        [self.downBtn1.leadingAnchor constraintEqualToAnchor:contentRow1.leadingAnchor],
        
        [self.downBtn2.topAnchor constraintEqualToAnchor:contentRow1.topAnchor],
        [self.downBtn2.bottomAnchor constraintEqualToAnchor:contentRow1.bottomAnchor],
        [self.downBtn2.leadingAnchor constraintEqualToAnchor:self.downBtn1.trailingAnchor constant:10],
        [self.downBtn2.widthAnchor constraintEqualToAnchor:self.downBtn1.widthAnchor],
        
        [self.downBtn3.topAnchor constraintEqualToAnchor:contentRow1.topAnchor],
        [self.downBtn3.bottomAnchor constraintEqualToAnchor:contentRow1.bottomAnchor],
        [self.downBtn3.leadingAnchor constraintEqualToAnchor:self.downBtn2.trailingAnchor constant:10],
        [self.downBtn3.trailingAnchor constraintEqualToAnchor:contentRow1.trailingAnchor],
        [self.downBtn3.widthAnchor constraintEqualToAnchor:self.downBtn1.widthAnchor],
    ]];
    
    // Content button group - row 2
    UIView *contentRow2 = [[UIView alloc] init];
    contentRow2.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainContent addSubview:contentRow2];
    
    self.downBtn4 = [self createContentButton:@"新增按钮1"];
    self.downBtn5 = [self createContentButton:@"新增按钮2"];
    self.downBtn6 = [self createContentButton:@"新增按钮3"];
    [contentRow2 addSubview:self.downBtn4];
    [contentRow2 addSubview:self.downBtn5];
    [contentRow2 addSubview:self.downBtn6];
    
    [NSLayoutConstraint activateConstraints:@[
        [contentRow2.topAnchor constraintEqualToAnchor:contentRow1.bottomAnchor constant:16],
        [contentRow2.leadingAnchor constraintEqualToAnchor:self.mainContent.leadingAnchor constant:10],
        [contentRow2.trailingAnchor constraintEqualToAnchor:self.mainContent.trailingAnchor constant:-10],
        [contentRow2.heightAnchor constraintEqualToConstant:44],
        
        [self.downBtn4.topAnchor constraintEqualToAnchor:contentRow2.topAnchor],
        [self.downBtn4.bottomAnchor constraintEqualToAnchor:contentRow2.bottomAnchor],
        [self.downBtn4.leadingAnchor constraintEqualToAnchor:contentRow2.leadingAnchor],
        
        [self.downBtn5.topAnchor constraintEqualToAnchor:contentRow2.topAnchor],
        [self.downBtn5.bottomAnchor constraintEqualToAnchor:contentRow2.bottomAnchor],
        [self.downBtn5.leadingAnchor constraintEqualToAnchor:self.downBtn4.trailingAnchor constant:10],
        [self.downBtn5.widthAnchor constraintEqualToAnchor:self.downBtn4.widthAnchor],
        
        [self.downBtn6.topAnchor constraintEqualToAnchor:contentRow2.topAnchor],
        [self.downBtn6.bottomAnchor constraintEqualToAnchor:contentRow2.bottomAnchor],
        [self.downBtn6.leadingAnchor constraintEqualToAnchor:self.downBtn5.trailingAnchor constant:10],
        [self.downBtn6.trailingAnchor constraintEqualToAnchor:contentRow2.trailingAnchor],
        [self.downBtn6.widthAnchor constraintEqualToAnchor:self.downBtn4.widthAnchor],
    ]];
    
    [self.downBtn1 addTarget:self action:@selector(downBtn1Tapped) forControlEvents:UIControlEventTouchUpInside];
    [self.downBtn2 addTarget:self action:@selector(downBtn2Tapped) forControlEvents:UIControlEventTouchUpInside];
    [self.downBtn3 addTarget:self action:@selector(downBtn3Tapped) forControlEvents:UIControlEventTouchUpInside];
    [self.downBtn4 addTarget:self action:@selector(downBtn4Tapped) forControlEvents:UIControlEventTouchUpInside];
    [self.downBtn5 addTarget:self action:@selector(downBtn5Tapped) forControlEvents:UIControlEventTouchUpInside];
    [self.downBtn6 addTarget:self action:@selector(downBtn6Tapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Start button
    UIView *startWrap = [[UIView alloc] init];
    startWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainContent addSubview:startWrap];
    
    self.startBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.startBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startBtn setTitle:@"启动" forState:UIControlStateNormal];
    [self.startBtn setTitleColor:[UIColor colorWithRed:0.204 green:0.780 blue:0.349 alpha:1.0] forState:UIControlStateNormal];
    self.startBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.startBtn.backgroundColor = [UIColor colorWithRed:0.941 green:0.969 blue:0.941 alpha:1.0];
    self.startBtn.layer.cornerRadius = 12;
    self.startBtn.enabled = NO;
    [self.startBtn addTarget:self action:@selector(startBtnTapped) forControlEvents:UIControlEventTouchUpInside];
    [startWrap addSubview:self.startBtn];
    
    [NSLayoutConstraint activateConstraints:@[
        [startWrap.topAnchor constraintEqualToAnchor:contentRow2.bottomAnchor constant:24],
        [startWrap.leadingAnchor constraintEqualToAnchor:self.mainContent.leadingAnchor],
        [startWrap.trailingAnchor constraintEqualToAnchor:self.mainContent.trailingAnchor],
        [startWrap.bottomAnchor constraintEqualToAnchor:self.mainContent.bottomAnchor constant:-20],
        
        [self.startBtn.centerXAnchor constraintEqualToAnchor:startWrap.centerXAnchor],
        [self.startBtn.topAnchor constraintEqualToAnchor:startWrap.topAnchor],
        [self.startBtn.bottomAnchor constraintEqualToAnchor:startWrap.bottomAnchor],
        [self.startBtn.widthAnchor constraintEqualToConstant:120],
        [self.startBtn.heightAnchor constraintEqualToConstant:44],
    ]];
    
    [self.mainContent.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
}

#pragma mark - Log Container

- (void)setupLogContainer:(UIView *)parent {
    self.logContainer = [[UIView alloc] init];
    self.logContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.logContainer.backgroundColor = [UIColor colorWithRed:0.973 green:0.976 blue:0.980 alpha:1.0]; // #f8f9fa
    self.logContainer.layer.cornerRadius = 18;
    self.logContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.logContainer.layer.shadowOpacity = 0.06;
    self.logContainer.layer.shadowOffset = CGSizeMake(0, 4);
    self.logContainer.layer.shadowRadius = 16;
    self.logContainer.clipsToBounds = YES;
    [parent addSubview:self.logContainer];
    
    // Log title
    self.logTitle = [[UILabel alloc] init];
    self.logTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.logTitle.text = @"运行日志";
    self.logTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.logTitle.textColor = [UIColor colorWithRed:0.173 green:0.173 blue:0.180 alpha:1.0]; // #2c2c2e
    [self.logContainer addSubview:self.logTitle];
    
    // Blink line
    self.blinkLine = [[UIView alloc] init];
    self.blinkLine.translatesAutoresizingMaskIntoConstraints = NO;
    self.blinkLine.backgroundColor = [UIColor colorWithRed:0 green:0.478 blue:1.0 alpha:1.0]; // #007aff
    [self.logContainer addSubview:self.blinkLine];
    [self startBlinkAnimation];
    
    // Log scroll view
    self.logScrollView = [[UIScrollView alloc] init];
    self.logScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logScrollView.showsVerticalScrollIndicator = NO;
    self.logScrollView.showsHorizontalScrollIndicator = NO;
    [self.logContainer addSubview:self.logScrollView];
    
    self.logContentView = [[UIView alloc] init];
    self.logContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.logScrollView addSubview:self.logContentView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.logTitle.topAnchor constraintEqualToAnchor:self.logContainer.topAnchor constant:14],
        [self.logTitle.leadingAnchor constraintEqualToAnchor:self.logContainer.leadingAnchor constant:20],
        [self.logTitle.trailingAnchor constraintEqualToAnchor:self.logContainer.trailingAnchor constant:-20],
        
        [self.blinkLine.topAnchor constraintEqualToAnchor:self.logTitle.bottomAnchor constant:14],
        [self.blinkLine.leadingAnchor constraintEqualToAnchor:self.logContainer.leadingAnchor constant:20],
        [self.blinkLine.trailingAnchor constraintEqualToAnchor:self.logContainer.trailingAnchor constant:-20],
        [self.blinkLine.heightAnchor constraintEqualToConstant:1],
        
        [self.logScrollView.topAnchor constraintEqualToAnchor:self.blinkLine.bottomAnchor constant:16],
        [self.logScrollView.leadingAnchor constraintEqualToAnchor:self.logContainer.leadingAnchor constant:20],
        [self.logScrollView.trailingAnchor constraintEqualToAnchor:self.logContainer.trailingAnchor constant:-20],
        [self.logScrollView.heightAnchor constraintEqualToConstant:200],
        [self.logScrollView.bottomAnchor constraintEqualToAnchor:self.logContainer.bottomAnchor],
        
        [self.logContentView.topAnchor constraintEqualToAnchor:self.logScrollView.topAnchor],
        [self.logContentView.bottomAnchor constraintEqualToAnchor:self.logScrollView.bottomAnchor],
        [self.logContentView.leadingAnchor constraintEqualToAnchor:self.logScrollView.leadingAnchor],
        [self.logContentView.trailingAnchor constraintEqualToAnchor:self.logScrollView.trailingAnchor],
        [self.logContentView.widthAnchor constraintEqualToAnchor:self.logScrollView.widthAnchor],
    ]];
}

#pragma mark - Helper: Create Buttons

- (UIButton *)createIOSButton:(NSString *)title {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithRed:0.204 green:0.780 blue:0.349 alpha:1.0] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    btn.backgroundColor = [UIColor colorWithRed:0.941 green:0.969 blue:0.941 alpha:1.0];
    btn.layer.cornerRadius = 14;
    btn.enabled = NO;
    return btn;
}

- (UIButton *)createContentButton:(NSString *)title {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithRed:0.204 green:0.780 blue:0.349 alpha:1.0] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    btn.backgroundColor = [UIColor colorWithRed:0.941 green:0.969 blue:0.941 alpha:1.0];
    btn.layer.cornerRadius = 12;
    btn.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    btn.enabled = NO;
    return btn;
}

#pragma mark - Animations

- (void)performEntryAnimations {
    // Header card - spreadIn
    self.headerCard.alpha = 0;
    self.headerCard.transform = CGAffineTransformMakeScale(0.3, 0.3);
    [UIView animateWithDuration:0.9 delay:0.1 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        self.headerCard.alpha = 1;
        self.headerCard.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    // Main content - shrinkIn
    self.mainContent.alpha = 0;
    self.mainContent.transform = CGAffineTransformMakeScale(1.4, 1.4);
    [UIView animateWithDuration:0.8 delay:0.3 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        self.mainContent.alpha = 1;
        self.mainContent.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    // Read button - pulseBtn
    self.readBtn.alpha = 0;
    self.readBtn.transform = CGAffineTransformMakeScale(0.2, 0.2);
    [UIView animateWithDuration:0.7 delay:0.7 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{
        self.readBtn.alpha = 1;
        self.readBtn.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    // Init button - pulseBtn
    self.resetBtn.alpha = 0;
    self.resetBtn.transform = CGAffineTransformMakeScale(0.2, 0.2);
    [UIView animateWithDuration:0.7 delay:0.9 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:0 animations:^{
        self.resetBtn.alpha = 1;
        self.resetBtn.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    // Log container - staggerIn
    self.logContainer.alpha = 0;
    self.logContainer.transform = CGAffineTransformConcat(
        CGAffineTransformMakeTranslation(-100, 0),
        CGAffineTransformMakeScale(0.9, 0.9)
    );
    [UIView animateWithDuration:0.8 delay:0.5 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        self.logContainer.alpha = 1;
        self.logContainer.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)startBlinkAnimation {
    [UIView animateWithDuration:1.0 delay:0 options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse animations:^{
        self.blinkLine.alpha = 0.4;
    } completion:nil];
}

#pragma mark - Button Actions

- (void)activateTapped {
    NSString *key = [self.activateInput.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if ([key isEqualToString:self.correctKey]) {
        // Show expire tips
        self.expireTips.hidden = NO;
        [UIView animateWithDuration:0.2 animations:^{
            self.expireTips.alpha = 1;
        }];
        
        [self addLog:@"卡密验证通过，激活成功"];
        
        // Device info
        NSString *device = [[UIDevice currentDevice] model];
        NSString *iosVer = [[UIDevice currentDevice] systemVersion];
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        CGFloat scale = [UIScreen mainScreen].scale;
        NSString *screenStr = [NSString stringWithFormat:@"%.0f × %.0f", screenSize.width * scale, screenSize.height * scale];
        
        [self addLog:[NSString stringWithFormat:@"设备类型：%@", device]];
        [self addLog:[NSString stringWithFormat:@"iOS 系统版本：%@", iosVer]];
        [self addLog:[NSString stringWithFormat:@"屏幕分辨率：%@", screenStr]];
        
        // Enable kernel buttons
        self.readBtn.enabled = YES;
        self.resetBtn.enabled = YES;
    } else {
        // Hide expire tips
        [UIView animateWithDuration:0.2 animations:^{
            self.expireTips.alpha = 0;
        } completion:^(BOOL finished) {
            self.expireTips.hidden = YES;
        }];
        
        [self addLog:@"卡密错误，所有功能无法使用！"];
        
        // Disable all
        self.readBtn.enabled = NO;
        self.resetBtn.enabled = NO;
        self.downBtn1.enabled = NO;
        self.downBtn2.enabled = NO;
        self.downBtn3.enabled = NO;
        self.downBtn4.enabled = NO;
        self.downBtn5.enabled = NO;
        self.downBtn6.enabled = NO;
        self.startBtn.enabled = NO;
    }
    
    [self.activateInput resignFirstResponder];
}

- (void)readBtnTapped {
    [self addLog:@"收到指令，准备启动读写服务"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self addLog:@"加载读写驱动模块"];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self addLog:@"权限校验通过"];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self addLog:@"内核读写通道已完全开启"];
        // Mark as finish - grey style
        self.readBtn.enabled = NO;
        self.readBtn.backgroundColor = [UIColor colorWithRed:0.914 green:0.914 blue:0.922 alpha:1.0]; // #e9e9eb
        [self.readBtn setTitleColor:[UIColor colorWithRed:0.557 green:0.557 blue:0.576 alpha:1.0] forState:UIControlStateNormal]; // #8e8e93
        [self.readBtn setTitleColor:[UIColor colorWithRed:0.557 green:0.557 blue:0.576 alpha:1.0] forState:UIControlStateDisabled];
        self.readDone = YES;
        [self checkUnlock];
    });
}

- (void)resetBtnTapped {
    [self addLog:@"即将执行内核重置操作"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self addLog:@"清空临时缓存数据"];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self addLog:@"内核参数恢复默认值"];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self addLog:@"内核初始化全部完成"];
        // Mark as finish - grey style
        self.resetBtn.enabled = NO;
        self.resetBtn.backgroundColor = [UIColor colorWithRed:0.914 green:0.914 blue:0.922 alpha:1.0];
        [self.resetBtn setTitleColor:[UIColor colorWithRed:0.557 green:0.557 blue:0.576 alpha:1.0] forState:UIControlStateNormal];
        [self.resetBtn setTitleColor:[UIColor colorWithRed:0.557 green:0.557 blue:0.576 alpha:1.0] forState:UIControlStateDisabled];
        self.initDone = YES;
        [self checkUnlock];
    });
}

- (void)checkUnlock {
    if (self.readDone && self.initDone) {
        self.downBtn1.enabled = YES;
        self.downBtn2.enabled = YES;
        self.downBtn3.enabled = YES;
        self.downBtn4.enabled = YES;
        self.downBtn5.enabled = YES;
        self.downBtn6.enabled = YES;
        self.startBtn.enabled = YES;
        [self addLog:@"内核服务全部就绪，所有功能已解锁"];
    }
}

- (void)downBtn1Tapped { [self createProgressForButton:@"测试测试(测试)"]; }
- (void)downBtn2Tapped { [self createProgressForButton:@"测试测试(测试)"]; }
- (void)downBtn3Tapped { [self createProgressForButton:@"测试测试(测试)"]; }
- (void)downBtn4Tapped { [self createProgressForButton:@"新增按钮1"]; }
- (void)downBtn5Tapped { [self createProgressForButton:@"新增按钮2"]; }
- (void)downBtn6Tapped { [self createProgressForButton:@"新增按钮3"]; }

- (void)startBtnTapped {
    [self addLog:@"点击启动按钮"];
}

#pragma mark - Progress

- (void)createProgressForButton:(NSString *)btnName {
    [self addLog:[NSString stringWithFormat:@"%@ 开始下载", btnName]];
    
    UILabel *progressLabel = [[UILabel alloc] init];
    progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    progressLabel.font = [UIFont systemFontOfSize:13];
    progressLabel.textColor = [UIColor blackColor];
    progressLabel.text = @"";
    [self.logContentView addSubview:progressLabel];
    
    UIView *lastView = nil;
    NSArray *subviews = self.logContentView.subviews;
    if (subviews.count > 1) {
        lastView = subviews[subviews.count - 2];
    }
    
    if (lastView) {
        [progressLabel.topAnchor constraintEqualToAnchor:lastView.bottomAnchor constant:4].active = YES;
    } else {
        [progressLabel.topAnchor constraintEqualToAnchor:self.logContentView.topAnchor].active = YES;
    }
    [progressLabel.leadingAnchor constraintEqualToAnchor:self.logContentView.leadingAnchor].active = YES;
    [progressLabel.trailingAnchor constraintEqualToAnchor:self.logContentView.trailingAnchor].active = YES;
    [progressLabel.bottomAnchor constraintEqualToAnchor:self.logContentView.bottomAnchor].active = YES;
    
    __block int progress = 0;
    int total = 20;
    
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        progress++;
        NSMutableString *bar = [NSMutableString string];
        for (int i = 0; i < progress; i++) {
            [bar appendString:@">"];
        }
        int percent = (int)((float)progress / total * 100);
        progressLabel.text = [NSString stringWithFormat:@"[%@] [进度] %@ %d%%", [self getNowTime], bar, percent];
        
        [self.logScrollView layoutIfNeeded];
        CGFloat bottomOffset = self.logContentView.frame.size.height - self.logScrollView.frame.size.height;
        if (bottomOffset > 0) {
            [self.logScrollView setContentOffset:CGPointMake(0, bottomOffset) animated:NO];
        }
        
        if (progress >= total) {
            [t invalidate];
            [self addLog:[NSString stringWithFormat:@"%@ 下载完成", btnName]];
        }
    }];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

#pragma mark - Log

- (void)addLog:(NSString *)text {
    NSString *time = [self getNowTime];
    NSString *fullText = [NSString stringWithFormat:@"[%@] %@", time, text];
    
    UILabel *logLine = [[UILabel alloc] init];
    logLine.translatesAutoresizingMaskIntoConstraints = NO;
    logLine.text = fullText;
    logLine.font = [UIFont systemFontOfSize:13];
    logLine.textColor = [UIColor blackColor];
    logLine.numberOfLines = 0;
    
    // Remove previous bottom constraint
    for (NSLayoutConstraint *c in self.logContentView.constraints) {
        if (c.firstAttribute == NSLayoutAttributeBottom || c.secondAttribute == NSLayoutAttributeBottom) {
            if (c.firstItem == self.logContentView || c.secondItem == self.logContentView) {
                [self.logContentView removeConstraint:c];
            }
        }
    }
    
    [self.logContentView addSubview:logLine];
    
    UIView *lastView = nil;
    NSArray *subviews = self.logContentView.subviews;
    if (subviews.count > 1) {
        lastView = subviews[subviews.count - 2];
    }
    
    if (lastView) {
        [logLine.topAnchor constraintEqualToAnchor:lastView.bottomAnchor constant:4].active = YES;
    } else {
        [logLine.topAnchor constraintEqualToAnchor:self.logContentView.topAnchor].active = YES;
    }
    [logLine.leadingAnchor constraintEqualToAnchor:self.logContentView.leadingAnchor].active = YES;
    [logLine.trailingAnchor constraintEqualToAnchor:self.logContentView.trailingAnchor].active = YES;
    [logLine.bottomAnchor constraintEqualToAnchor:self.logContentView.bottomAnchor].active = YES;
    
    [self.logScrollView layoutIfNeeded];
    CGFloat bottomOffset = self.logContentView.frame.size.height - self.logScrollView.frame.size.height;
    if (bottomOffset > 0) {
        [self.logScrollView setContentOffset:CGPointMake(0, bottomOffset) animated:YES];
    }
}

- (NSString *)getNowTime {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    return [formatter stringFromDate:[NSDate date]];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self activateTapped];
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

#pragma mark - Status Bar

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

@end
