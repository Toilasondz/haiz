#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "HVSonMenu.h"
#import "HVSonEngine.h"

static const CGFloat kMenuW      = 280.0;
static const CGFloat kMenuH      = 400.0;
static const CGFloat kMenuCorner = 20.0;
static const CGFloat kBtnSize    = 48.0;

#pragma mark - HVSonMenuView

@interface HVSonMenuView ()
@property (nonatomic, strong) UIView *contentArea;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation HVSonMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self _setup];
    }
    return self;
}

- (void)_setup {
    self.backgroundColor     = [UIColor whiteColor];
    self.layer.cornerRadius  = kMenuCorner;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth   = 0.5;
    self.layer.borderColor   = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    self.clipsToBounds       = YES;

    /* ---------- Title ---------- */
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text          = @"H Van Son";
    title.font          = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    title.textColor     = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];

    /* ---------- Subtitle ---------- */
    UILabel *sub = [[UILabel alloc] init];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.text          = @"VideoStar Tool";
    sub.font          = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    sub.textColor     = [UIColor colorWithWhite:0.55 alpha:1.0];
    sub.textAlignment = NSTextAlignmentCenter;
    [self addSubview:sub];

    /* ---------- Close button ---------- */
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [close addTarget:self action:@selector(_closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:close];

    /* ---------- Separator ---------- */
    UIView *sep = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [UIColor colorWithWhite:0 alpha:0.08];
    [self addSubview:sep];

    /* ---------- Content area ---------- */
    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.tag = 0x777;
    self.contentArea = content;
    [self addSubview:content];

    /* ---------- Status label ---------- */
    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.text          = @"";
    status.font          = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    status.textColor     = [UIColor colorWithWhite:0.45 alpha:1.0];
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 2;
    self.statusLabel = status;
    [self addSubview:status];

    /* ---------- Constraints ---------- */
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor       constraintEqualToAnchor:self.topAnchor      constant:22],
        [title.leadingAnchor   constraintEqualToAnchor:self.leadingAnchor  constant:16],
        [title.trailingAnchor  constraintEqualToAnchor:self.trailingAnchor constant:-16],

        [sub.topAnchor         constraintEqualToAnchor:title.bottomAnchor  constant:2],
        [sub.leadingAnchor     constraintEqualToAnchor:self.leadingAnchor  constant:16],
        [sub.trailingAnchor    constraintEqualToAnchor:self.trailingAnchor constant:-16],

        [close.topAnchor       constraintEqualToAnchor:self.topAnchor      constant:14],
        [close.trailingAnchor  constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [close.widthAnchor     constraintEqualToConstant:24],
        [close.heightAnchor    constraintEqualToConstant:24],

        [sep.topAnchor         constraintEqualToAnchor:sub.bottomAnchor    constant:14],
        [sep.leadingAnchor     constraintEqualToAnchor:self.leadingAnchor  constant:16],
        [sep.trailingAnchor    constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [sep.heightAnchor      constraintEqualToConstant:1],

        [content.topAnchor     constraintEqualToAnchor:sep.bottomAnchor    constant:12],
        [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor  constant:14],
        [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [content.heightAnchor  constraintEqualToConstant:4 * 48.0],

        [status.topAnchor      constraintEqualToAnchor:content.bottomAnchor constant:8],
        [status.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor  constant:16],
        [status.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [status.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor   constant:-14],
    ]];

    /* ---------- Feature buttons ---------- */
    [self _buildFeatureButtons];

    /* ---------- Drag gesture ---------- */
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(_onPan:)];
    pan.cancelsTouchesInView = NO;
    [self addGestureRecognizer:pan];

    /* ---------- Status callback ---------- */
    __weak typeof(self) weakSelf = self;
    [HVSonEngine shared].onStatus = ^(NSString *msg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (s) s.statusLabel.text = msg ?: @"";
        });
    };
}

- (void)_buildFeatureButtons {
    NSArray<NSString *> *titles = @[
        @"📷  Auto nhập ảnh vào lớp",
        @"🕘  Code gần nhất",
        @"🎵  Auto chia beat",
        @"🎬  Auto nhập code & ảnh phân cảnh",
    ];
    NSArray<NSString *> *sels = @[@"_tap0", @"_tap1", @"_tap2", @"_tap3"];

    UIView *content = self.contentArea;
    CGFloat y = 0;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(0, y, 252, 44);
        b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        b.backgroundColor  = [UIColor colorWithRed:0.96 green:0.97 blue:1.00 alpha:1.0];
        b.layer.cornerRadius = 10;
        b.layer.masksToBounds = YES;
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0]
                forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        b.tag = 100 + i;
        [b addTarget:self
              action:NSSelectorFromString(sels[i])
    forControlEvents:UIControlEventTouchUpInside];
        [content addSubview:b];
        y += 48;
    }
}

- (void)_closeTapped {
    if (self.onClose) self.onClose();
}

- (void)_onPan:(UIPanGestureRecognizer *)g {
    UIView *sv = self.superview;
    if (!sv) return;
    CGPoint t = [g translationInView:sv];
    CGPoint c = self.center;
    c.x += t.x;
    c.y += t.y;

    CGFloat halfW = self.bounds.size.width  * 0.5;
    CGFloat halfH = self.bounds.size.height * 0.5;
    CGFloat topSafe = 40.0;
    CGFloat botSafe = 40.0;
    c.x = MAX(halfW + 4.0, MIN(c.x, sv.bounds.size.width  - halfW - 4.0));
    c.y = MAX(halfH + topSafe, MIN(c.y, sv.bounds.size.height - halfH - botSafe));

    self.center = c;
    [g setTranslation:CGPointZero inView:sv];
}

#pragma mark - Feature taps

- (void)_tap0 { [[HVSonEngine shared] feature0AutoImportImages]; }
- (void)_tap1 { [[HVSonEngine shared] feature1ShowLastCode];     }
- (void)_tap2 { [[HVSonEngine shared] feature2AutoBeatSplit];    }
- (void)_tap3 { [[HVSonEngine shared] feature3AutoMultiScene];   }

@end

#pragma mark - HVSonToggleButton

@implementation HVSonToggleButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor     = [UIColor whiteColor];
        self.layer.cornerRadius  = frame.size.width * 0.5;
        self.layer.masksToBounds = NO;
        self.layer.borderWidth   = 1.0;
        self.layer.borderColor   = [UIColor colorWithWhite:0 alpha:0.15].CGColor;
        self.layer.shadowColor   = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.20;
        self.layer.shadowRadius  = 6.0;
        self.layer.shadowOffset  = CGSizeMake(0, 2);
        self.titleLabel.font     = [UIFont boldSystemFontOfSize:13];
        [self setTitle:@"VS" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    }
    return self;
}

@end

#pragma mark - HVSonRootViewController

@interface HVSonRootViewController ()
@property (nonatomic, assign) CGPoint btnPanStart;
@end

@implementation HVSonRootViewController

- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    root.backgroundColor = [UIColor clearColor];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    CGFloat w = root.bounds.size.width;
    CGRect f = CGRectMake(w - kBtnSize - 20, 120, kBtnSize, kBtnSize);
    HVSonToggleButton *btn = [[HVSonToggleButton alloc] initWithFrame:f];
    [btn addTarget:self action:@selector(_toggleMenu) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *btnPan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(_onButtonPan:)];
    btnPan.cancelsTouchesInView = NO;
    [btn addGestureRecognizer:btnPan];

    self.toggleButton = btn;
    [root addSubview:btn];
}

- (void)_toggleMenu {
    if (self.menuView.superview) {
        [self.menuView removeFromSuperview];
        self.menuView = nil;
        return;
    }
    CGSize s = self.view.bounds.size;
    CGRect f = CGRectMake((s.width  - kMenuW) * 0.5,
                          (s.height - kMenuH) * 0.5,
                          kMenuW, kMenuH);
    HVSonMenuView *menu = [[HVSonMenuView alloc] initWithFrame:f];
    __weak typeof(self) weakSelf = self;
    menu.onClose = ^{
        __strong typeof(weakSelf) sSelf = weakSelf;
        if (!sSelf) return;
        [sSelf.menuView removeFromSuperview];
        sSelf.menuView = nil;
    };
    self.menuView = menu;
    [self.view addSubview:menu];
}

- (void)_onButtonPan:(UIPanGestureRecognizer *)g {
    UIView *sv = self.view;
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            self.btnPanStart = self.toggleButton.center;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint t = [g translationInView:sv];
            CGPoint c = self.btnPanStart;
            c.x += t.x;
            c.y += t.y;
            CGFloat half = kBtnSize * 0.5;
            c.x = MAX(half + 4.0, MIN(c.x, sv.bounds.size.width  - half - 4.0));
            c.y = MAX(half + 40.0, MIN(c.y, sv.bounds.size.height - half - 40.0));
            self.toggleButton.center = c;
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            self.btnPanStart = self.toggleButton.center;
            break;
        default:
            break;
    }
}

- (BOOL)shouldAutorotate { return YES; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

@end

#pragma mark - HVSonWindow

@implementation HVSonWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    if (hit == self.rootViewController.view) return nil;
    return hit;
}

@end