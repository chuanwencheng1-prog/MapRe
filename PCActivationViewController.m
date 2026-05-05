//
//  PCActivationViewController.m
//  PersonalCenterUI
//
//  视觉：深蓝 #0b1220 背景 + 翠绿 #16a34a 主按钮 + 琥珀 #f59e0b 强调；
//       严格屏蔽紫色（包括 tintColor、placeholder、边框等均手动指定）。
//

#import "PCActivationViewController.h"
#import "PCAuthManager.h"

static inline UIColor *PCA_RGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF)/255.0
                           green:((rgb >>  8) & 0xFF)/255.0
                            blue:( rgb        & 0xFF)/255.0
                           alpha:1.0];
}

@interface PCActivationViewController ()
@property (nonatomic, strong) UIView       *card;
@property (nonatomic, strong) UILabel      *titleLabel;
@property (nonatomic, strong) UILabel      *subLabel;
@property (nonatomic, strong) UITextField  *codeField;
@property (nonatomic, strong) UILabel      *fpLabel;
@property (nonatomic, strong) UILabel      *statusLabel;
@property (nonatomic, strong) UIButton     *submitBtn;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation PCActivationViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 根视图与全局 tintColor（屏蔽系统紫色）
    self.view.backgroundColor = PCA_RGB(0x0b1220);
    self.view.tintColor       = PCA_RGB(0x16a34a);
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;

    [self buildUI];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_kbShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_kbHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    CGFloat W = UIScreen.mainScreen.bounds.size.width;
    CGFloat cardW = MIN(W - 32, 380);

    self.card = [[UIView alloc] init];
    self.card.backgroundColor   = PCA_RGB(0x0f172a);
    self.card.layer.cornerRadius = 18.0;
    self.card.layer.borderWidth  = 1.0 / UIScreen.mainScreen.scale;
    self.card.layer.borderColor  = PCA_RGB(0x1e293b).CGColor;
    self.card.layer.shadowColor  = [UIColor blackColor].CGColor;
    self.card.layer.shadowOpacity = 0.35;
    self.card.layer.shadowOffset  = CGSizeMake(0, 10);
    self.card.layer.shadowRadius  = 24;
    [self.view addSubview:self.card];

    // 顶部 Logo 条
    UIView *logoBar = [[UIView alloc] init];
    [self.card addSubview:logoBar];
    UIView *accent = [[UIView alloc] init];
    accent.backgroundColor = PCA_RGB(0x16a34a);
    accent.layer.cornerRadius = 3;
    [logoBar addSubview:accent];
    UILabel *logo = [[UILabel alloc] init];
    logo.text = @"PersonalCenterUI · 激活";
    logo.textColor = [UIColor whiteColor];
    logo.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [logoBar addSubview:logo];

    // 主标题
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"请输入激活码";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    [self.card addSubview:self.titleLabel];

    self.subLabel = [[UILabel alloc] init];
    self.subLabel.text = @"激活码一经绑定与本设备一一对应，更换设备请联系客服。";
    self.subLabel.textColor = PCA_RGB(0x94a3b8);
    self.subLabel.font = [UIFont systemFontOfSize:12];
    self.subLabel.numberOfLines = 0;
    [self.card addSubview:self.subLabel];

    // 输入框
    self.codeField = [[UITextField alloc] init];
    self.codeField.placeholder = @"XXXX-XXXX-XXXX-XXXX-XXXX";
    self.codeField.textColor   = [UIColor whiteColor];
    self.codeField.font        = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.codeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.codeField.autocorrectionType     = UITextAutocorrectionTypeNo;
    self.codeField.spellCheckingType      = UITextSpellCheckingTypeNo;
    self.codeField.keyboardType           = UIKeyboardTypeASCIICapable;
    self.codeField.keyboardAppearance     = UIKeyboardAppearanceDark;
    self.codeField.returnKeyType          = UIReturnKeyGo;
    self.codeField.backgroundColor        = PCA_RGB(0x0b1628);
    self.codeField.layer.cornerRadius     = 10;
    self.codeField.layer.borderColor      = PCA_RGB(0x1e293b).CGColor;
    self.codeField.layer.borderWidth      = 1.0;
    self.codeField.tintColor              = PCA_RGB(0x16a34a);
    self.codeField.leftView  = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 1)];
    self.codeField.leftViewMode = UITextFieldViewModeAlways;
    // 暗色 placeholder（避免默认淡紫）
    NSAttributedString *ph = [[NSAttributedString alloc] initWithString:self.codeField.placeholder attributes:@{
        NSForegroundColorAttributeName: PCA_RGB(0x475569),
        NSFontAttributeName: self.codeField.font,
    }];
    self.codeField.attributedPlaceholder = ph;
    self.codeField.delegate = (id)self;
    [self.codeField addTarget:self action:@selector(_return) forControlEvents:UIControlEventEditingDidEndOnExit];
    [self.card addSubview:self.codeField];

    // 设备指纹
    self.fpLabel = [[UILabel alloc] init];
    NSString *fp = [[PCAuthManager sharedManager] deviceFingerprint];
    self.fpLabel.text = [NSString stringWithFormat:@"设备指纹：%@…", [fp substringToIndex:MIN(16, fp.length)]];
    self.fpLabel.textColor = PCA_RGB(0x64748b);
    self.fpLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self.card addSubview:self.fpLabel];

    // 状态
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textColor = PCA_RGB(0xfca5a5);
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.card addSubview:self.statusLabel];

    // 激活按钮
    self.submitBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.submitBtn setTitle:@"激  活" forState:UIControlStateNormal];
    [self.submitBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.submitBtn.titleLabel.font    = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.submitBtn.backgroundColor    = PCA_RGB(0x16a34a);
    self.submitBtn.layer.cornerRadius = 12;
    self.submitBtn.tintColor          = [UIColor whiteColor];
    [self.submitBtn addTarget:self action:@selector(_onSubmit) forControlEvents:UIControlEventTouchUpInside];
    [self.card addSubview:self.submitBtn];

    // loading
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    [self.submitBtn addSubview:self.spinner];

    // 版权
    UILabel *ft = [[UILabel alloc] init];
    ft.text = @"© PersonalCenterUI · 严格按当地法律法规使用";
    ft.textColor = PCA_RGB(0x475569);
    ft.font = [UIFont systemFontOfSize:10];
    ft.textAlignment = NSTextAlignmentCenter;
    [self.card addSubview:ft];

    // Layout
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-10],
        [self.card.widthAnchor   constraintEqualToConstant:cardW],
    ]];

    UIView *c = self.card;
    for (UIView *v in @[logoBar, accent, logo, self.titleLabel, self.subLabel, self.codeField,
                        self.fpLabel, self.statusLabel, self.submitBtn, self.spinner, ft]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
    }
    [NSLayoutConstraint activateConstraints:@[
        [logoBar.topAnchor      constraintEqualToAnchor:c.topAnchor      constant:16],
        [logoBar.leadingAnchor  constraintEqualToAnchor:c.leadingAnchor  constant:18],
        [logoBar.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-18],
        [logoBar.heightAnchor   constraintEqualToConstant:22],

        [accent.leadingAnchor   constraintEqualToAnchor:logoBar.leadingAnchor],
        [accent.centerYAnchor   constraintEqualToAnchor:logoBar.centerYAnchor],
        [accent.widthAnchor     constraintEqualToConstant:6],
        [accent.heightAnchor    constraintEqualToConstant:18],

        [logo.leadingAnchor     constraintEqualToAnchor:accent.trailingAnchor constant:8],
        [logo.centerYAnchor     constraintEqualToAnchor:logoBar.centerYAnchor],

        [self.titleLabel.topAnchor      constraintEqualToAnchor:logoBar.bottomAnchor constant:16],
        [self.titleLabel.leadingAnchor  constraintEqualToAnchor:c.leadingAnchor  constant:18],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-18],

        [self.subLabel.topAnchor        constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6],
        [self.subLabel.leadingAnchor    constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subLabel.trailingAnchor   constraintEqualToAnchor:self.titleLabel.trailingAnchor],

        [self.codeField.topAnchor       constraintEqualToAnchor:self.subLabel.bottomAnchor constant:16],
        [self.codeField.leadingAnchor   constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.codeField.trailingAnchor  constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.codeField.heightAnchor    constraintEqualToConstant:48],

        [self.fpLabel.topAnchor         constraintEqualToAnchor:self.codeField.bottomAnchor constant:8],
        [self.fpLabel.leadingAnchor     constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.fpLabel.trailingAnchor    constraintEqualToAnchor:self.titleLabel.trailingAnchor],

        [self.statusLabel.topAnchor     constraintEqualToAnchor:self.fpLabel.bottomAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],

        [self.submitBtn.topAnchor       constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [self.submitBtn.leadingAnchor   constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.submitBtn.trailingAnchor  constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.submitBtn.heightAnchor    constraintEqualToConstant:50],

        [self.spinner.centerXAnchor     constraintEqualToAnchor:self.submitBtn.centerXAnchor],
        [self.spinner.centerYAnchor     constraintEqualToAnchor:self.submitBtn.centerYAnchor],

        [ft.topAnchor                   constraintEqualToAnchor:self.submitBtn.bottomAnchor constant:14],
        [ft.leadingAnchor               constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [ft.trailingAnchor              constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [ft.bottomAnchor                constraintEqualToAnchor:c.bottomAnchor constant:-14],
    ]];
}

#pragma mark - Actions

- (void)_return { [self _onSubmit]; }
- (void)_dismissKeyboard { [self.view endEditing:YES]; }

- (void)_setLoading:(BOOL)loading {
    self.submitBtn.enabled = !loading;
    self.submitBtn.alpha   = loading ? 0.6 : 1.0;
    [self.submitBtn setTitle:loading ? @"" : @"激  活" forState:UIControlStateNormal];
    if (loading) [self.spinner startAnimating]; else [self.spinner stopAnimating];
    self.codeField.enabled = !loading;
}

- (void)_setStatus:(NSString *)msg ok:(BOOL)ok {
    self.statusLabel.text      = msg ?: @"";
    self.statusLabel.textColor = ok ? PCA_RGB(0x86efac) : PCA_RGB(0xfca5a5);
}

- (void)_onSubmit {
    [self _dismissKeyboard];
    NSString *code = [self.codeField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (code.length < 8) { [self _setStatus:@"请输入有效激活码" ok:NO]; return; }
    [self _setLoading:YES];
    [self _setStatus:@"正在校验…" ok:YES];

    __weak typeof(self) wself = self;
    [[PCAuthManager sharedManager] activateWithCode:code completion:^(BOOL success, NSString * _Nullable message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) self = wself;
            if (!self) return;
            [self _setLoading:NO];
            if (success) {
                [self _setStatus:message ?: @"激活成功" ok:YES];
                void(^cb)(void) = self.onActivated;
                [self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(); }];
            } else {
                [self _setStatus:message ?: @"激活失败" ok:NO];
            }
        });
    }];
}

#pragma mark - 键盘避让

- (void)_kbShow:(NSNotification *)n {
    NSValue *v = n.userInfo[UIKeyboardFrameEndUserInfoKey];
    CGFloat kbH = v.CGRectValue.size.height;
    CGFloat cardBottom = CGRectGetMaxY(self.card.frame);
    CGFloat screenH = self.view.bounds.size.height;
    CGFloat delta = cardBottom - (screenH - kbH) + 20;
    if (delta > 0) {
        [UIView animateWithDuration:0.25 animations:^{
            self.view.transform = CGAffineTransformMakeTranslation(0, -delta);
        }];
    }
}

- (void)_kbHide:(NSNotification *)n {
    [UIView animateWithDuration:0.25 animations:^{ self.view.transform = CGAffineTransformIdentity; }];
}

@end
