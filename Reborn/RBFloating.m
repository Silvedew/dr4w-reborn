#import "RBFloating.h"
#import "RBManager.h"
#import "RBPrefs.h"

#import <QuartzCore/QuartzCore.h>

@interface RBFloating ()
- (CGRect)clamped:(CGRect)f;
- (CGFloat)size;
- (UIImage *)icon;
- (BOOL)disabledHere;
@end

@implementation RBFloating {
    UIWindow *_win;
    UIView   *_ball;
    UIButton *_btn;
    BOOL      _userHidden;
    BOOL      _snapped;
    NSInteger _fadeGen;
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

- (CGFloat)size {
    return [RBPrefs ballSize];
}

- (void)buildIfNeeded {
    if (_win) return;
    CGFloat size = [self size];

    CGPoint c = [RBPrefs floatCenter];
    _win = [[UIWindow alloc] initWithFrame:[self clamped:CGRectMake(c.x - size / 2.0,
                                                                    c.y - size / 2.0,
                                                                    size, size)]];
    _win.windowScene = [self activeScene];
    _win.windowLevel = UIWindowLevelAlert + 900.0;
    _win.backgroundColor = [UIColor clearColor];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = [[UIView alloc] initWithFrame:_win.bounds];
    vc.view.backgroundColor = [UIColor clearColor];
    _win.rootViewController = vc;

    _ball = [[UIView alloc] initWithFrame:_win.bounds];
    _ball.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    _ball.layer.cornerRadius = size / 2.0;
    _ball.layer.cornerCurve = kCACornerCurveContinuous;
    _ball.layer.borderWidth = 0.5;
    _ball.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.15].CGColor;
    _ball.clipsToBounds = YES;
    _ball.alpha = [RBPrefs ballAlpha];
    [_win.rootViewController.view addSubview:_ball];

    _btn = [UIButton buttonWithType:UIButtonTypeSystem];
    _btn.frame = _ball.bounds;
    _btn.backgroundColor = [UIColor clearColor];
    _btn.tintColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    [_btn setImage:[self icon] forState:UIControlStateNormal];
    [_btn addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [_btn addTarget:self action:@selector(touchedDown)
   forControlEvents:UIControlEventTouchDown];

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

- (UIImage *)icon {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                        weight:UIImageSymbolWeightMedium];
    UIImage *img = [UIImage systemImageNamed:@"pencil.tip" withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:@"pencil.tip"];
    return img;
}

- (BOOL)disabledHere {
    return [RBPrefs isAppDisabled:[[NSBundle mainBundle] bundleIdentifier]];
}

- (BOOL)sceneActive {
    if (!_win) return YES;
    UIWindowScene *ws = (UIWindowScene *)_win.windowScene;
    if (!ws) return YES;
    return ws.activationState == UISceneActivationStateForegroundActive;
}

- (void)show {
    /* SpringBoard never owns a ball: it would float above apps as a dead twin */
    if (RBIsSpringBoard()) { _win.hidden = YES; return; }
    if ([self disabledHere]) { _win.hidden = YES; return; }
    @try {
        [self buildIfNeeded];
        /* split view: only the focused app shows a ball, so there is one */
        if (![self sceneActive]) { _win.hidden = YES; return; }
        _userHidden = NO;
        _win.hidden = NO;
        [self applyPrefs];
    } @catch (NSException *e) {
        NSLog(@"[Dr4wReborn] ball show failed: %@", e);
    }
}

- (void)hide {
    _win.hidden = YES;
}

- (void)refreshVisibility {
    if ([self disabledHere]) [self hide];
    else [self show];
}

- (CGRect)clamped:(CGRect)f {
    CGRect host = RBHostBounds();
    if (host.size.width < f.size.width + 16) host.size.width = f.size.width + 16;
    if (host.size.height < f.size.height + 16) host.size.height = f.size.height + 16;
    if (f.origin.x < 8.0) f.origin.x = 8.0;
    if (f.origin.y < 8.0) f.origin.y = 8.0;
    if (f.origin.x > host.size.width - f.size.width - 8.0)
        f.origin.x = host.size.width - f.size.width - 8.0;
    if (f.origin.y > host.size.height - f.size.height - 8.0)
        f.origin.y = host.size.height - f.size.height - 8.0;
    return f;
}

- (void)applyPrefs {
    if (!_win) return;
    CGFloat size = [self size];
    CGRect f = _win.frame;
    f.size = CGSizeMake(size, size);
    _win.frame = [self clamped:f];

    _ball.frame = CGRectMake(0, 0, size, size);
    _ball.layer.cornerRadius = size / 2.0;
    _btn.frame = _ball.bounds;
    [_btn setImage:[self icon] forState:UIControlStateNormal];
    if (!_snapped) _ball.alpha = [RBPrefs ballAlpha];
}

- (void)touchedDown {
    _ball.alpha = [RBPrefs ballAlpha];
    [self scheduleIdleFade];
}

- (void)scheduleIdleFade {
    _fadeGen++;
    NSInteger gen = _fadeGen;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) s = weakSelf;
        if (!s || s->_fadeGen != gen) return;
        if (s->_win && !s->_win.hidden) s->_ball.alpha = 0.45;
    });
}

- (void)tapped {
    if (_userHidden) return;
    [self touchedDown];
    [[RBManager shared] toggle];
}

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    _userHidden = YES;
    _win.hidden = YES;
}

- (void)panned:(UIPanGestureRecognizer *)g {
    if (!_win) return;
    CGFloat size = [self size];

    CGPoint t = [g translationInView:_win];
    CGRect f = _win.frame;
    f.origin.x += t.x;
    f.origin.y += t.y;

    CGRect host = RBHostBounds();
    if (f.origin.x < 8.0) f.origin.x = 8.0;
    if (f.origin.y < 8.0) f.origin.y = 8.0;
    if (f.origin.x > host.size.width - size - 8.0) f.origin.x = host.size.width - size - 8.0;
    if (f.origin.y > host.size.height - size - 8.0) f.origin.y = host.size.height - size - 8.0;

    if (g.state == UIGestureRecognizerStateEnded ||
        g.state == UIGestureRecognizerStateCancelled) {
        /* snap flush to a side and dim, like a screen-edge tab */
        if (f.origin.x <= 24.0) { f.origin.x = 0.0; _snapped = YES; }
        else if (f.origin.x >= host.size.width - size - 24.0) {
            f.origin.x = host.size.width - size;
            _snapped = YES;
        } else {
            _snapped = NO;
        }
        _ball.alpha = _snapped ? 0.45 : [RBPrefs ballAlpha];
        [RBPrefs setFloatCenter:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f))];
    }

    _win.frame = f;

    CGPoint zero;
    zero.x = 0.0;
    zero.y = 0.0;
    [g setTranslation:zero inView:_win];
}

@end
