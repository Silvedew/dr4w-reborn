#import "RBFloating.h"
#import "RBManager.h"
#import "RBPrefs.h"

#import <QuartzCore/QuartzCore.h>

static CGFloat const kSize = 56.0;

#pragma mark - pass-through window

/* The window itself must return nil for touches that miss the ball, otherwise
   UIWindow falls back to "return self" and swallows the whole screen. */
@interface RBFloatWindow : UIWindow
@end

@implementation RBFloatWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self) return nil;
    return v;
}
@end

@interface RBFloatRoot : UIView
@end

@implementation RBFloatRoot
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return (v == self) ? nil : v;
}
@end

#pragma mark - floating ball

@implementation RBFloating {
    RBFloatWindow *_win;
    UIView *_ball;
    UIButton *_btn;
    BOOL _userHidden;
}

+ (instancetype)shared {
    static RBFloating *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[RBFloating alloc] init]; });
    return shared;
}

- (UIWindowScene *)activeScene {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    }
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

- (void)buildIfNeeded {
    if (_win) return;

    _win = [[RBFloatWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowScene = [self activeScene];
    _win.windowLevel = UIWindowLevelAlert + 9.0;
    _win.backgroundColor = [UIColor clearColor];

    RBFloatRoot *root = [[RBFloatRoot alloc] initWithFrame:_win.bounds];
    root.backgroundColor = [UIColor clearColor];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = root;
    _win.rootViewController = vc;

    /* frosted glass ball */
    _ball = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kSize, kSize)];
    _ball.backgroundColor = [UIColor clearColor];

    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:
                                 [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    glass.frame = _ball.bounds;
    glass.layer.cornerRadius = kSize / 2.0;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.borderWidth = 0.5;
    glass.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    glass.clipsToBounds = YES;
    glass.userInteractionEnabled = NO;
    [_ball addSubview:glass];

    _btn = [UIButton buttonWithType:UIButtonTypeSystem];
    _btn.frame = _ball.bounds;
    _btn.backgroundColor = [UIColor clearColor];
    _btn.tintColor = [UIColor colorWithWhite:0.10 alpha:1.0];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                        weight:UIImageSymbolWeightMedium];
    UIImage *icon = [UIImage systemImageNamed:@"pencil.tip" withConfiguration:cfg];
    if (!icon) icon = [UIImage systemImageNamed:@"pencil.tip"];
    [_btn setImage:icon forState:UIControlStateNormal];

    [_btn addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(panned:)];
    [_btn addGestureRecognizer:pan];

    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(longPressed:)];
    press.minimumPressDuration = 0.6;
    [_btn addGestureRecognizer:press];

    [_ball addSubview:_btn];
    [root addSubview:_ball];

    CGPoint c = [RBPrefs floatCenter];
    CGFloat half = kSize / 2.0;
    if (c.x < half) c.x = half;
    if (c.y < half) c.y = half;
    if (c.x > root.bounds.size.width - half) c.x = root.bounds.size.width - half;
    if (c.y > root.bounds.size.height - half) c.y = root.bounds.size.height - half;
    _ball.center = c;
}

- (void)show {
    [self buildIfNeeded];
    _userHidden = NO;
    _win.frame = [UIScreen mainScreen].bounds;
    _win.rootViewController.view.frame = _win.bounds;
    _win.hidden = NO;
}

- (void)hide {
    _win.hidden = YES;
}

- (void)tapped {
    if (_userHidden) return;
    [[RBManager shared] toggle];
}

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    _userHidden = YES;
    _win.hidden = YES;
    NSLog(@"[Dr4wReborn] floating ball hidden");
}

- (void)panned:(UIPanGestureRecognizer *)g {
    UIView *host = _ball.superview;
    if (!host) return;

    CGPoint t = [g translationInView:host];
    CGPoint c = _ball.center;
    c.x += t.x;
    c.y += t.y;

    CGFloat half = kSize / 2.0;
    if (c.x < half + 8.0) c.x = half + 8.0;
    if (c.y < half + 8.0) c.y = half + 8.0;
    if (c.x > host.bounds.size.width - half - 8.0) c.x = host.bounds.size.width - half - 8.0;
    if (c.y > host.bounds.size.height - half - 8.0) c.y = host.bounds.size.height - half - 8.0;

    _ball.center = c;

    CGPoint zero;
    zero.x = 0.0;
    zero.y = 0.0;
    [g setTranslation:zero inView:host];

    if (g.state == UIGestureRecognizerStateEnded ||
        g.state == UIGestureRecognizerStateCancelled) {
        [RBPrefs setFloatCenter:c];
    }
}

@end
