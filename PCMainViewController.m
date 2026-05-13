//
//  PCMainViewController.m
//  PersonalCenterUI
//
//  wy.html 像素级 1:1 还原：
//    - 顶部渐变标题栏（56pt，#1677ff → #0958d9）
//    - 4 张白色圆角 20 菜单卡片，margin-bottom 16
//    - 一级行高 60，左侧 32x32 图标（圆角 10），右侧 ⌄ 箭头（展开旋转 180°）
//    - 二级行高 14/24 padding，底部 1pt 分隔；右侧 #00b96b 圆角"确定"按钮
//    - 点击"确定" → 弹出居中进度弹窗并触发 PCPakDownloader 下载
//

#import "PCMainViewController.h"
#import "PCDownloadPopView.h"
#import "PCPakDownloader.h"
#import "PCAuthPopView.h"
#import "PCAuthManager.h"
#import <objc/runtime.h>

#pragma mark - Colors

static inline UIColor *HEX(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF)/255.0
                           green:((rgb >>  8) & 0xFF)/255.0
                            blue:( rgb        & 0xFF)/255.0
                           alpha:1.0];
}
__attribute__((unused))
static inline UIColor *HEXA(uint32_t rgb, CGFloat a) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF)/255.0
                           green:((rgb >>  8) & 0xFF)/255.0
                            blue:( rgb        & 0xFF)/255.0
                           alpha:a];
}

#pragma mark - MenuCard View

@interface PCMenuCardView : UIView
@property (nonatomic, strong) UIView     *firstRow;      // .menu-first
@property (nonatomic, strong) UIView     *iconBox;       // .icon
@property (nonatomic, strong) UILabel    *iconLabel;     // icon emoji
@property (nonatomic, strong) UILabel    *titleLabel;    // .title
@property (nonatomic, strong) UILabel    *arrowLabel;    // .arrow
@property (nonatomic, strong) UIView     *secondWrap;    // .menu-second
@property (nonatomic, strong) NSArray<UIView *>  *subItems;
@property (nonatomic, assign) BOOL        expanded;
@property (nonatomic, copy)   void (^onSubItemTap)(NSString *subTitle);
@property (nonatomic, copy)   void (^onToggle)(void);    // 展开/收起状态变化后通知主 VC 重排
- (void)setCardTitle:(NSString *)title
            iconText:(NSString *)iconText
           iconColor:(UIColor *)iconColor
            subItems:(NSArray<NSString *> *)items;
- (CGFloat)desiredHeight;
@end

@implementation PCMenuCardView

- (instancetype)init {
    if ((self = [super init])) {
        self.backgroundColor = [UIColor whiteColor];
        self.layer.cornerRadius  = 20.0;
        self.layer.masksToBounds = YES;     // overflow: hidden
        // 卡片阴影由 wrapper container 提供 —— UIView 自身 masksToBounds=YES 会裁掉阴影
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    // 一级行
    self.firstRow = [[UIView alloc] init];
    self.firstRow.backgroundColor = [UIColor whiteColor];
    self.firstRow.userInteractionEnabled = YES;
    [self addSubview:self.firstRow];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(toggle)];
    [self.firstRow addGestureRecognizer:tap];

    // 图标色块
    self.iconBox = [[UIView alloc] init];
    self.iconBox.layer.cornerRadius  = 10.0;
    self.iconBox.layer.masksToBounds = YES;
    [self.firstRow addSubview:self.iconBox];

    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.textAlignment = NSTextAlignmentCenter;
    self.iconLabel.font = [UIFont systemFontOfSize:16];
    self.iconLabel.textColor = [UIColor whiteColor];
    [self.iconBox addSubview:self.iconLabel];

    // 标题
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.textColor = HEX(0x333333);
    self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.firstRow addSubview:self.titleLabel];

    // 箭头
    self.arrowLabel = [[UILabel alloc] init];
    self.arrowLabel.text = @"⌄";
    self.arrowLabel.textColor = HEX(0x999999);
    self.arrowLabel.font = [UIFont systemFontOfSize:20];
    self.arrowLabel.textAlignment = NSTextAlignmentCenter;
    [self.firstRow addSubview:self.arrowLabel];

    // 二级容器
    self.secondWrap = [[UIView alloc] init];
    self.secondWrap.backgroundColor = HEX(0xFAFBFC);
    self.secondWrap.clipsToBounds = YES;
    [self addSubview:self.secondWrap];

    // 顶部 1pt 分割线
    UIView *topLine = [[UIView alloc] init];
    topLine.backgroundColor = HEX(0xF0F2F5);
    topLine.tag = 9001;
    [self.secondWrap addSubview:topLine];
}

- (void)setCardTitle:(NSString *)title
            iconText:(NSString *)iconText
           iconColor:(UIColor *)iconColor
            subItems:(NSArray<NSString *> *)items {
    self.titleLabel.text  = title;
    self.iconLabel.text   = iconText;
    self.iconBox.backgroundColor = iconColor;

    // 清掉旧的 sub items
    for (UIView *v in self.subItems) [v removeFromSuperview];

    NSMutableArray *arr = [NSMutableArray array];
    for (NSInteger i = 0; i < items.count; i++) {
        NSString *name = items[i];
        UIView *row = [[UIView alloc] init];
        row.backgroundColor = [UIColor clearColor];

        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = name;
        lbl.textColor = HEX(0x555555);
        lbl.font = [UIFont systemFontOfSize:14];
        lbl.tag = 1;
        [row addSubview:lbl];

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.backgroundColor = HEX(0x00B96B);
        btn.layer.cornerRadius = 14.0;          // 足够大以圆形两端
        btn.layer.masksToBounds = YES;
        [btn setTitle:@"执行" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12];
        btn.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
        btn.tag = 2;
        objc_setAssociatedObject(btn, @selector(tag), name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [btn addTarget:self action:@selector(onSubItemButtonTap:)
       forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:btn];

        // 底部 1pt 分隔线（最后一项不画）
        if (i < items.count - 1) {
            UIView *bottom = [[UIView alloc] init];
            bottom.backgroundColor = HEX(0xF0F2F5);
            bottom.tag = 3;
            [row addSubview:bottom];
        }
        [self.secondWrap addSubview:row];
        [arr addObject:row];
    }
    self.subItems = arr;
    [self setNeedsLayout];
}

- (void)onSubItemButtonTap:(UIButton *)btn {
    NSString *name = objc_getAssociatedObject(btn, @selector(tag));
    if (self.onSubItemTap) self.onSubItemTap(name ?: @"");
    // 按下视觉反馈
    [UIView animateWithDuration:0.12 animations:^{
        btn.transform = CGAffineTransformMakeScale(1.05, 1.05);
        btn.backgroundColor = HEX(0x00A85C);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.12 animations:^{
            btn.transform = CGAffineTransformIdentity;
            btn.backgroundColor = HEX(0x00B96B);
        }];
    }];
}

- (CGFloat)subItemRowHeight { return 48.0; /* 14*2 + 文字 20 */ }
- (CGFloat)secondWrapHeight {
    if (!self.expanded) return 0;
    return [self subItemRowHeight] * self.subItems.count + 1.0; // +topLine
}
- (CGFloat)desiredHeight {
    return 60.0 + [self secondWrapHeight];
}

- (void)toggle {
    self.expanded = !self.expanded;

    // 箭头动画（卡片自身维护）
    [UIView animateWithDuration:0.45 delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.arrowLabel.transform = self.expanded
            ? CGAffineTransformMakeRotation((CGFloat)M_PI)
            : CGAffineTransformIdentity;
        self.arrowLabel.textColor = self.expanded ? HEX(0x1677FF) : HEX(0x999999);
    } completion:nil];

    // 高度变化交给主 VC 来带动画重排：仅 setNeedsLayout+layoutIfNeeded
    // 靠 Window 或 self.view 无法保证子树同步重排（只有旋转时系统才会全量打标）。
    if (self.onToggle) self.onToggle();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;

    // 一级行
    self.firstRow.frame = CGRectMake(0, 0, W, 60);

    // 图标 32x32 + left padding 20
    self.iconBox.frame = CGRectMake(20, (60-32)/2.0, 32, 32);
    self.iconLabel.frame = self.iconBox.bounds;

    // 箭头 right 20, 尺寸 20
    self.arrowLabel.frame = CGRectMake(W - 20 - 20, (60-20)/2.0, 20, 20);

    // 标题：图标右 + gap 12
    CGFloat titleX = 20 + 32 + 12;
    self.titleLabel.frame = CGRectMake(titleX, 0,
                                       W - titleX - 40 - 12, 60);

    // 二级容器
    CGFloat h = [self secondWrapHeight];
    self.secondWrap.frame = CGRectMake(0, 60, W, h);
    UIView *topLine = [self.secondWrap viewWithTag:9001];
    topLine.frame = CGRectMake(0, 0, W, 1);

    CGFloat y = 1;
    CGFloat rowH = [self subItemRowHeight];
    for (UIView *row in self.subItems) {
        row.frame = CGRectMake(0, y, W, rowH);
        y += rowH;
        UILabel *lbl = [row viewWithTag:1];
        UIButton *btn = (UIButton *)[row viewWithTag:2];
        UIView *bottom = [row viewWithTag:3];

        lbl.frame = CGRectMake(24, 0, W - 24 - 70 - 24, rowH);

        CGSize btnSize = [btn sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        CGFloat bw = MAX(btnSize.width, 56);
        CGFloat bh = MAX(btnSize.height, 28);
        btn.frame = CGRectMake(W - 24 - bw, (rowH - bh)/2.0, bw, bh);

        if (bottom) bottom.frame = CGRectMake(24, rowH - 1, W - 48, 1);
    }
}

@end

#pragma mark - Shadow container

@interface PCShadowContainer : UIView
@end
@implementation PCShadowContainer
- (instancetype)init {
    if ((self = [super init])) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.shadowColor   = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.06;
        self.layer.shadowRadius  = 9.0;      // 对应 CSS blur 18
        self.layer.shadowOffset  = CGSizeMake(0, 4);
        self.layer.masksToBounds = NO;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // 阴影 path 提效
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                       cornerRadius:20.0].CGPath;
    for (UIView *sub in self.subviews) sub.frame = self.bounds;
}
@end

#pragma mark - Main VC

@interface PCMainViewController ()
@property (nonatomic, strong) UIView              *headerBar;        // .app-header
@property (nonatomic, strong) CAGradientLayer     *headerGradient;
@property (nonatomic, strong) UILabel             *headerTitle;
@property (nonatomic, strong) UIScrollView        *scroll;           // .main-wrap
@property (nonatomic, strong) NSMutableArray<UIView *>     *cardWrappers;  // shadow containers
@property (nonatomic, strong) NSMutableArray<PCMenuCardView *> *cards;
@property (nonatomic, strong) PCDownloadPopView   *pop;

// ====== 授权相关 ======
@property (nonatomic, strong) PCAuthPopView       *authPop;
@property (nonatomic, assign) BOOL                 authPresented;   // 已在本次展示过卡密弹窗
@property (nonatomic, assign) BOOL                 authorized;      // 已通过授权

// ====== 私有方法声明（消除预声明警告）======
- (void)handleSubItemTap:(NSString *)name fromCard:(PCMenuCardView * _Nullable)card;
- (void)_rebuildCardsFromConfig:(NSArray *)cfg;
- (NSArray *)_mapRemoteMenus:(NSArray *)remote;
- (NSArray *)_currentMenuConfigArray;
- (void)_refreshRemoteMenusIfNeeded;
@end

@implementation PCMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = HEX(0xF6F8FA);
    [self buildHeader];
    [self buildScroll];
    [self buildCards];
    self.pop = [[PCDownloadPopView alloc] init];
}

- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

#pragma mark - Auth

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self presentAuthIfNeeded];
}

- (void)presentAuthIfNeeded {
    if (self.authorized) return;
    if (self.authPresented) return;
    if (self.authPop && self.authPop.superview) return;
    self.authPresented = YES;

    // 在主 VC 自身 view 上 addSubview 卡密弹窗
    // —— 背景即是插件 UI（修复“弹在 Filza 上”的问题）
    self.authPop = [[PCAuthPopView alloc] init];
    __weak typeof(self) ws = self;
    [self.authPop presentFromVC:self onAuthorized:^{
        __strong typeof(ws) ss = ws;
        if (!ss) return;
        ss.authorized = YES;
        ss.authPop = nil;
        [ss startAuthHeartbeat];
        // 授权成功 → 异步拉取远程菜单配置（首次或更新时无感替换）
        [ss _refreshRemoteMenusIfNeeded];
    }];
}

- (void)startAuthHeartbeat {
    __weak typeof(self) ws = self;
    [[PCAuthManager sharedManager] startHeartbeatWithInterval:300
                                                     onKicked:^(NSString * _Nullable reason) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) ss = ws; if (!ss) return;
            [[PCAuthManager sharedManager] stopHeartbeat];
            [ss showAuthExpiredAlert:reason];
        });
    }];
}

- (void)showAuthExpiredAlert:(NSString *)reason {
    UIAlertController *al = [UIAlertController
        alertControllerWithTitle:@"授权失效"
                         message:reason ?: @"授权已到期，需重新激活"
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) ws = self;
    [al addAction:[UIAlertAction actionWithTitle:@"重新激活"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction * _Nonnull a) {
        __strong typeof(ws) ss = ws; if (!ss) return;
        ss.authorized = NO;
        ss.authPresented = NO;
        [ss presentAuthIfNeeded];
    }]];
    UIViewController *top = self;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:al animated:YES completion:nil];
}

#pragma mark - UI

- (void)buildHeader {
    self.headerBar = [[UIView alloc] init];
    self.headerBar.clipsToBounds = NO;
    // 阴影 0 2 12 rgba(9,88,217,0.18)
    self.headerBar.layer.shadowColor   = HEX(0x0958D9).CGColor;
    self.headerBar.layer.shadowOpacity = 0.18;
    self.headerBar.layer.shadowRadius  = 6.0;
    self.headerBar.layer.shadowOffset  = CGSizeMake(0, 2);
    [self.view addSubview:self.headerBar];

    self.headerGradient = [CAGradientLayer layer];
    // 135deg 渐变：start 左上、end 右下
    self.headerGradient.colors = @[ (id)HEX(0x1677FF).CGColor,
                                    (id)HEX(0x0958D9).CGColor ];
    self.headerGradient.startPoint = CGPointMake(0, 0);
    self.headerGradient.endPoint   = CGPointMake(1, 1);
    [self.headerBar.layer addSublayer:self.headerGradient];

    self.headerTitle = [[UILabel alloc] init];
    self.headerTitle.text = @"超凡";
    self.headerTitle.textColor = [UIColor whiteColor];
    self.headerTitle.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.headerTitle.textAlignment = NSTextAlignmentCenter;
    [self.headerBar addSubview:self.headerTitle];
}

- (void)buildScroll {
    self.scroll = [[UIScrollView alloc] init];
    self.scroll.backgroundColor = HEX(0xF6F8FA);
    self.scroll.alwaysBounceVertical = YES;
    self.scroll.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0, *)) {
        self.scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.view addSubview:self.scroll];
}

- (void)buildCards {
    self.cardWrappers = [NSMutableArray array];
    self.cards = [NSMutableArray array];

    // 1) 先用本地缓存（无则往硬编码默认）渲染，保证秒打开
    NSArray *cfg = [self _currentMenuConfigArray];
    [self _rebuildCardsFromConfig:cfg];
}

/// 按优先级： 远程缓存 → 硬编码默认
- (NSArray *)_currentMenuConfigArray {
    NSDictionary *cached = [[PCAuthManager sharedManager] cachedRemoteConfig];
    NSArray *remoteMenus = [cached[@"menus"] isKindOfClass:[NSArray class]] ? cached[@"menus"] : nil;
    if (remoteMenus.count > 0) {
        return [self _mapRemoteMenus:remoteMenus];
    }
    return [self _defaultHardcodedMenus];
}

/// 将远程 JSON（id/title/icon/color/items:[title/url]）转为 与硬编码格式一致的数组
- (NSArray *)_mapRemoteMenus:(NSArray *)remote {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *m in remote) {
        if (![m isKindOfClass:[NSDictionary class]]) continue;
        NSString *title = [m[@"title"] isKindOfClass:[NSString class]] ? m[@"title"] : @"";
        NSString *icon  = [m[@"icon"]  isKindOfClass:[NSString class]] ? m[@"icon"]  : @"📋";
        NSString *colorStr = [m[@"color"] isKindOfClass:[NSString class]] ? m[@"color"] : @"#1677FF";
        UIColor *color = [self _colorFromHexString:colorStr] ?: HEX(0x1677FF);

        NSMutableArray *subTitles = [NSMutableArray array];
        NSMutableDictionary *urlMap = [NSMutableDictionary dictionary];
        NSArray *items = [m[@"items"] isKindOfClass:[NSArray class]] ? m[@"items"] : @[];
        for (NSDictionary *it in items) {
            if (![it isKindOfClass:[NSDictionary class]]) continue;
            NSString *t = [it[@"title"] isKindOfClass:[NSString class]] ? it[@"title"] : nil;
            NSString *u = [it[@"url"]   isKindOfClass:[NSString class]] ? it[@"url"]   : nil;
            if (!t.length) continue;
            [subTitles addObject:t];
            if (u.length) urlMap[t] = u;
        }
        if (!title.length || subTitles.count == 0) continue;
        [out addObject:@{@"title":title, @"icon":icon, @"color":color,
                         @"items":subTitles, @"urls":urlMap}];
    }
    return out;
}

/// 硬编码内置默认（首次进入 & 远程拉取前的兼容回退）
- (NSArray *)_defaultHardcodedMenus {
    return @[
        @{ @"title":@"海岛地图", @"icon":@"📋", @"color":HEX(0x1677FF),
           @"items":@[@"海岛除草", @"海岛全除"],
           @"urls" :@{} },
        @{ @"title":@"上色配置", @"icon":@"👤", @"color":HEX(0x00B96B),
           @"items":@[@"人物上色"],
           @"urls" :@{} },
    ];
}

- (UIColor *)_colorFromHexString:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *s = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (s.length != 6) return nil;
    unsigned int rgb = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    if (![sc scanHexInt:&rgb]) return nil;
    return HEX(rgb);
}

/// 根据 cfg 数组重建所有卡片（远程拉取到新配置时会重调）
- (void)_rebuildCardsFromConfig:(NSArray *)cfg {
    // 清空旧视图
    for (UIView *w in self.cardWrappers) [w removeFromSuperview];
    [self.cardWrappers removeAllObjects];
    [self.cards removeAllObjects];

    __weak typeof(self) weakSelf = self;
    for (NSDictionary *c in cfg) {
        PCShadowContainer *wrap = [[PCShadowContainer alloc] init];
        PCMenuCardView *card = [[PCMenuCardView alloc] init];
        [card setCardTitle:c[@"title"]
                  iconText:c[@"icon"]
                 iconColor:c[@"color"]
                  subItems:c[@"items"]];
        // 用关联对象保留每张卡的 “子项标题 → 直链bt URL” 局部映射
        NSDictionary *urls = [c[@"urls"] isKindOfClass:[NSDictionary class]] ? c[@"urls"] : @{};
        objc_setAssociatedObject(card, @selector(subItemDownloadMap),
                                 urls, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        card.onSubItemTap = ^(NSString *name) {
            [weakSelf handleSubItemTap:name fromCard:card];
        };
        card.onToggle = ^{
            [weakSelf relayoutCardsAnimated:YES];
        };
        [wrap addSubview:card];
        [self.scroll addSubview:wrap];
        [self.cardWrappers addObject:wrap];
        [self.cards addObject:card];
    }
    [self relayoutCardsAnimated:NO];
}

/// 异步拉取远程配置，成功则重建（平滑切换）
- (void)_refreshRemoteMenusIfNeeded {
    __weak typeof(self) ws = self;
    [[PCAuthManager sharedManager] fetchRemoteConfigWithCompletion:^(NSDictionary * _Nullable config, NSError * _Nullable error) {
        if (error || !config) return;
        __strong typeof(ws) ss = ws; if (!ss) return;
        NSArray *remote = [config[@"menus"] isKindOfClass:[NSArray class]] ? config[@"menus"] : @[];
        NSArray *mapped = [ss _mapRemoteMenus:remote];
        if (mapped.count == 0) return; // 远程空配置 → 保留当前本地/默认
        // 仅在配置有变化时才重建，避免闪烁
        NSArray *cur = [ss _currentRenderedTitlesSnapshot];
        NSArray *next = [ss _renderedTitlesSnapshotFromConfig:mapped];
        if ([cur isEqualToArray:next]) return;
        [ss _rebuildCardsFromConfig:mapped];
    }];
}

- (NSArray *)_currentRenderedTitlesSnapshot {
    NSMutableArray *r = [NSMutableArray array];
    for (PCMenuCardView *c in self.cards) {
        [r addObject:c.titleLabel.text ?: @""];
    }
    return r;
}
- (NSArray *)_renderedTitlesSnapshotFromConfig:(NSArray *)cfg {
    NSMutableArray *r = [NSMutableArray array];
    for (NSDictionary *c in cfg) [r addObject:c[@"title"] ?: @""];
    return r;
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHeaderAndScroll];
    [self relayoutCardsAnimated:NO];
}

- (void)layoutHeaderAndScroll {
    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;

    // 状态栏 + 56 pt 标题栏
    CGFloat statusH = 0;
    if (@available(iOS 11.0, *)) statusH = self.view.safeAreaInsets.top;
    if (statusH < 20) statusH = 20;
    CGFloat headerH = statusH + 56;
    self.headerBar.frame = CGRectMake(0, 0, W, headerH);
    self.headerGradient.frame = self.headerBar.bounds;
    self.headerTitle.frame = CGRectMake(0, statusH, W, 56);

    // margin-top 68 ≈ header 56 + gap 12；这里 scroll 从 headerH 开始
    CGFloat scrollY = headerH;
    self.scroll.frame = CGRectMake(0, scrollY, W, H - scrollY);
}

/// 按每个卡片当前的 desiredHeight 重新排 wrapper + scroll contentSize。
/// 展开/收起时传 YES 带动画；viewDidLayoutSubviews 内传 NO。
- (void)relayoutCardsAnimated:(BOOL)animated {
    if (self.cards.count == 0) return;

    CGFloat W = self.view.bounds.size.width;
    CGFloat pad = 14;
    CGFloat gapTop = 12;

    void (^block)(void) = ^{
        CGFloat y = gapTop;
        for (NSInteger i = 0; i < self.cards.count; i++) {
            PCMenuCardView *card = self.cards[i];
            UIView *wrap = self.cardWrappers[i];
            CGFloat ch = [card desiredHeight];
            wrap.frame = CGRectMake(pad, y, W - pad * 2, ch);
            // 推动 PCShadowContainer 立即向下同步 card.frame，再由 card.layoutSubviews
            // 重算 secondWrap 高度 → 二级视图展开就能看见了
            [wrap setNeedsLayout];
            [wrap layoutIfNeeded];
            y += ch + 16; // margin-bottom
        }
        y = y - 16 + 40 /* safe-bottom 40 */ + 30 /* padding-bottom 30 */;
        self.scroll.contentSize = CGSizeMake(W, y);
    };

    if (animated) {
        [UIView animateWithDuration:0.45 delay:0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:block
                         completion:nil];
    } else {
        block();
    }
}

#pragma mark - Actions

/// ==========================================================================
/// 【自定义配置区】每个二级菜单项的独立直链
///
///   键  = buildCards 里 cfg.items 的中文名（二级菜单文字，必须一字不差）
///   值  = 对应直链字符串（空 / 未配 → 回退到 PCPakDownloader.m 的 kPCPakDownloadURL）
///
///   注：保存名一律使用下载完成后服务器/系统返回的原始文件名（NSURLResponse.suggestedFilename），不再手动配置。
///   其它配置（Bundle ID、Paks 子目录、覆盖策略）仍在 PCPakDownloader.m 统一管理。
/// ==========================================================================
- (NSDictionary<NSString *, NSString *> *)subItemDownloadMap {
    return @{
        // ────海岛地图 ────
        @"海岛除草":     @"https://modelscope-resouces.oss-cn-zhangjiakou.aliyuncs.com/avatar%2F4ff7550a-c7db-4e57-adc5-ad9891b13014.pak",
        @"海岛全除":   @"https://modelscope-resouces.oss-cn-zhangjiakou.aliyuncs.com/avatar%2F7c9770d3-67b4-440d-bd46-8f788663ef75.pak",

        // ────上色配置 ────
        @"人物上色": @"https://modelscope-resouces.oss-cn-zhangjiakou.aliyuncs.com/avatar%2Fb8a6cedb-0f50-482b-83d0-4a7d13af8de2.pak",
    };
}

- (void)handleSubItemTap:(NSString *)name {
    [self handleSubItemTap:name fromCard:nil];
}

- (void)handleSubItemTap:(NSString *)name fromCard:(PCMenuCardView *)card {
    // 未授权时不允许触发下载
    if (!self.authorized) {
        [self presentAuthIfNeeded];
        return;
    }
    NSString *title = [NSString stringWithFormat:@"正在执行：%@", name];
    [self.pop showInView:self.view title:title];

    // URL 查找优先级：
    //   1) 远程配置写在本卡关联对象上的 urls
    //   2) 本地硬编码 subItemDownloadMap
    //   3) 都没配 → PCPakDownloader 回退默认直链
    NSString *mapped = nil;
    if (card) {
        NSDictionary *urls = objc_getAssociatedObject(card, @selector(subItemDownloadMap));
        if ([urls isKindOfClass:[NSDictionary class]]) mapped = urls[name];
    }
    if (!mapped.length) {
        mapped = [self subItemDownloadMap][name];
    }
    NSString *overrideU = ([mapped isKindOfClass:[NSString class]] && mapped.length > 0) ? mapped : nil;

    // 真实下载 pak 到自定义路径（逻辑沿用 yy1.ipa 分析报告）
    [[PCPakDownloader sharedDownloader] startDownloadWithTitle:name
        overrideURL:overrideU
        progress:^(double progress, int64_t received, int64_t total) {
            NSString *tip = nil;
            double p100 = progress * 100;
            if (p100 >= 99.5)     tip = @"核心校验中...";
            else if (p100 > 40)   tip = [NSString stringWithFormat:@"核心处理中... (%lld / %lld)",
                                         (long long)received, (long long)total];
            else                  tip = @"请勿退出...";
            [self.pop updateProgress:progress tip:tip];
        } completion:^(BOOL success, NSString * _Nullable finalPath, NSError * _Nullable error) {
            if (success) {
                [self.pop updateProgress:1.0 tip:@"操作完成！"];
                // 1 秒后自动关闭
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [self.pop dismiss];
                });
            } else {
                NSString *msg = error.localizedDescription ?: @"未知错误";
                [self.pop updateProgress:0.0 tip:[NSString stringWithFormat:@"失败：%@", msg]];
            }
        }];
}

@end
