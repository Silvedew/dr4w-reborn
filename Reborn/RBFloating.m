#import "RBFloating.h"
#import "RBManager.h"
#import "RBPrefs.h"

#import <QuartzCore/QuartzCore.h>
#import <notify.h>

static CGFloat const kSize = 56.0;

@implementation RBFloating {
    UIWindow *_win;          /* exactly as big as the ball */
    UIView   *_ball;
    UIButton *_btn;
    BOOL      _userHidden;
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

    CGPoint c = [RBPrefs floatCenter];
    _win = [[UIWindow alloc] initWithFrame:CGRectMake(c.x - kSize / 2.0,
                                                      c.y - kSize / 2.0,
                                                      kSize, kSize)];
    _win.windowScene = [self activeScene];
    _win.windowLevel = UIWindowLevelAlert + 900.0;
    _win.backgroundColor = [UIColor clearColor];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = [[UIView alloc] initWithFrame:_win.bounds];
    vc.view.backgroundColor = [UIColor clearColor];
    _win.rootViewController = vc;

    _ball = [[UIView alloc] initWithFrame:_win.bounds];
    _ball.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    _ball.layer.cornerRadius = kSize / 2.0;
    _ball.layer.cornerCurve = kCACornerCurveContinuous;
    _ball.layer.borderWidth = 0.5;
    _ball.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.12].CGColor;
    _ball.clipsToBounds = YES;
    [_win.rootViewController.view addSubview:_ball];

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
}

- (void)show {
    [self buildIfNeeded];
    _userHidden = NO;
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
    NSLog(@"[Dr4wReborn] ball hidden");
}

- (void)panned:(UIPanGestureRecognizer *)g {
    if (!_win) return;

    CGPoint t = [g translationInView:_win];
    CGRect f = _win.frame;
    f.origin.x += t.x;
    f.origin.y += t.y;

    CGRect screen = [UIScreen mainScreen].bounds;
    if (f.origin.x < 8.0) f.origin.x = 8.0;
    if (f.origin.y < 8.0) f.origin.y = 8.0;
    if (f.origin.x > screen.size.width - kSize - 8.0) f.origin.x = screen.size.width - kSize - 8.0;
    if (f.origin.y > screen.size.height - kSize - 8.0) f.origin.y = screen.size.height - kSize - 8.0;
    _win.frame = f;

    CGPoint zero;
    zero.x = 0.0;
    zero.y = 0.0;
    [g setTranslation:zero inView:_win];

    if (g.state == UIGestureRecognizerStateEnded ||
        g.state == UIGestureRecognizerStateCancelled) {
        [RBPrefs setFloatCenter:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f))];
    }
}

@end
