#import "RBFloating.h"
#import "RBManager.h"
#import "RBPrefs.h"
#import "RBPolicy.h"
#import "RBIconStyle.h"
#import "RBDiagnostics.h"
#import "RBChrome.h"
#import "RBFloatingLayout.h"

#import <QuartzCore/QuartzCore.h>

@interface RBFloating ()
- (CGRect)clamped:(CGRect)f;
- (id<UICoordinateSpace>)hostSpace;
- (void)placeWindowAt:(CGPoint)center;
- (void)layoutBall;
- (CGFloat)size;
- (UIImage *)icon;
- (BOOL)disabledHere;
- (void)buildForScene:(UIWindowScene *)scene;
@end

@interface RBFloatingController : UIViewController
@property (nonatomic, weak) RBFloating *owner;
@end

@implementation RBFloatingController
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.owner layoutBall];
}
- (void)viewWillTransitionToSize:(CGSize)size
    withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.owner applyPrefs];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.owner applyPrefs];
    }];
}
@end

@implementation RBFloating {
    UIWindow *_win;
    UIView   *_ball;
    UIButton *_btn;
    BOOL      _userHidden;
    BOOL      _snapped;
    NSInteger _fadeGen;
    CGPoint   _center;
}

+ (instancetype)shared {
    static RBFloating *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[RBFloating alloc] init]; });
    return shared;
}

- (UIWindowScene *)activeScene {
    if (_win.windowScene && _win.windowScene.activationState == UISceneActivationStateForegroundActive &&
        [[UIApplication sharedApplication].connectedScenes containsObject:_win.windowScene])
        return _win.windowScene;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    }
    return nil;
}

- (CGFloat)size {
    return [RBPrefs ballSize];
}

- (void)buildIfNeeded {
    [self buildForScene:[self activeScene]];
}

- (void)buildForScene:(UIWindowScene *)scene {
    if (!RBPolicyCanHostWindow(scene != nil, [UIApplication sharedApplication].connectedScenes.count)) {
        RBDiagnostic(@"ball.skipped", @"no-active-scene");
        return;
    }
    if (_win && _win.windowScene == scene) return;
    _win.hidden = YES;
    _win.rootViewController = nil;
    _win = nil;
    _snapped = NO;
    CGFloat size = [self size];

    _center = [RBPrefs floatCenter];
    _win = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    if (scene) _win.windowScene = scene;
    _win.windowLevel = UIWindowLevelAlert + 900.0;
    _win.backgroundColor = [UIColor clearColor];
    _win.opaque = NO;
    _win.clipsToBounds = YES;

    RBFloatingController *vc = [[RBFloatingController alloc] init];
    vc.owner = self;
    vc.view = [[UIView alloc] initWithFrame:_win.bounds];
    vc.view.backgroundColor = [UIColor clearColor];
    vc.view.opaque = NO;
    vc.view.clipsToBounds = YES;
    _win.rootViewController = vc;

    _ball = [[RBChromeSurface alloc] initWithFrame:_win.bounds];
    _ball.opaque = NO;
    _ball.layer.cornerRadius = size / 2.0;
    _ball.layer.cornerCurve = kCACornerCurveContinuous;
    _ball.clipsToBounds = YES;
    _ball.alpha = [RBPrefs ballAlpha];
    [_win.rootViewController.view addSubview:_ball];

    _btn = [[RBChromeButton alloc] initWithFrame:CGRectZero];
    _btn.frame = _ball.bounds;
    _btn.backgroundColor = [UIColor clearColor];
    _btn.tintColor = UIColor.labelColor;
    _btn.accessibilityLabel = @"打开全局画板";
    _btn.accessibilityHint = @"可拖动调整位置，长按临时隐藏";
    _btn.largeContentTitle = @"全局画板";
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
    [self applyPrefs];
}

- (UIImage *)icon {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:24.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:@RB_PENCIL_SYMBOL withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:@RB_PENCIL_SYMBOL];
    return img;
}

- (BOOL)disabledHere {
    return [RBPrefs isAppDisabled:[[NSBundle mainBundle] bundleIdentifier]];
}

- (void)show {
    /* SpringBoard never owns a ball: it would float above apps as a dead twin */
    if (RBIsSpringBoard()) { _win.hidden = YES; return; }
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        _win.hidden = YES;
        RBDiagnostic(@"ball.skipped", @"not-foreground");
        return;
    }
    if ([[RBManager shared] isShowing]) { _win.hidden = YES; return; }
    if (!RBPolicyBall(![self disabledHere], _userHidden)) {
        _win.hidden = YES;
        RBDiagnostic(@"ball.skipped", [self disabledHere] ? @"app-disabled" : @"temporarily-hidden");
        return;
    }
    @try {
        [self buildIfNeeded];
        if (!_win) return;
        _win.hidden = NO;
        [self applyPrefs];
        RBDiagnostic(@"ball.shown", _win.windowScene ? @"scene=active" : @"scene=legacy");
    } @catch (NSException *e) {
        NSLog(@"[Dr4wReborn] ball show failed: %@", e);
    }
}

- (void)hide {
    _win.hidden = YES;
}

- (void)hideTemporarily {
    _userHidden = YES;
    [self hide];
}

- (void)restoreForForeground {
    _userHidden = NO;
    [self refreshVisibility];
}

- (void)sceneDidDeactivate:(UIScene *)scene {
    if (_win.windowScene == scene) [self hide];
}

- (void)refreshVisibility {
    if ([self disabledHere]) [self hide];
    else [self show];
}

- (void)updatePosition:(CGPoint)point fromWindow:(UIWindow *)sourceWindow {
    if (!sourceWindow || RBIsSpringBoard() || !isfinite(point.x) || !isfinite(point.y)) return;
    UIWindowScene *scene = sourceWindow.windowScene;
    if (scene && (scene.activationState != UISceneActivationStateForegroundActive ||
        ![UIApplication.sharedApplication.connectedScenes containsObject:scene])) return;
    [self buildForScene:scene];
    if (!_win || _win.windowScene != scene) return;
    id<UICoordinateSpace> hostSpace = [self hostSpace];
    CGPoint center = [hostSpace convertPoint:point fromCoordinateSpace:sourceWindow];
    if (!isfinite(center.x) || !isfinite(center.y)) return;
    CGRect host = hostSpace.bounds;
    RBFloatingOrigin clamped = RBClampFloatingCenter(center.x, center.y,
        host.origin.x, host.origin.y, host.size.width, host.size.height, [self size]);
    _center = CGPointMake(clamped.x, clamped.y);
    _snapped = NO;
    [RBPrefs setFloatCenter:_center];
    [self applyPrefs];
}

- (CGRect)clamped:(CGRect)f {
    CGRect host = [self hostSpace].bounds;
    RBFloatingOrigin origin = RBClampFloatingOrigin(f.origin.x, f.origin.y,
        host.origin.x, host.origin.y, host.size.width, host.size.height, f.size.width);
    f.origin = CGPointMake(origin.x, origin.y);
    return f;
}

- (id<UICoordinateSpace>)hostSpace {
    if (_win.windowScene) return _win.windowScene.coordinateSpace;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (!window.hidden && window.windowLevel == UIWindowLevelNormal && window.rootViewController)
            return window;
    }
    return _win.screen.coordinateSpace;
}

- (void)placeWindowAt:(CGPoint)center {
    // Convert a displacement to the window's parent axes without using its rotated frame.
    CGPoint local = [_win convertPoint:center fromCoordinateSpace:[self hostSpace]];
    CGSize delta = CGSizeApplyAffineTransform(CGSizeMake(local.x - CGRectGetMidX(_win.bounds),
        local.y - CGRectGetMidY(_win.bounds)), _win.transform);
    _win.center = CGPointMake(_win.center.x + delta.width, _win.center.y + delta.height);
}

- (void)layoutBall {
    CGFloat size = [self size];
    _ball.bounds = CGRectMake(0, 0, size, size);
    CGRect bounds = _win.rootViewController.view.bounds;
    _ball.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    _ball.layer.cornerRadius = size / 2.0;
    _btn.frame = _ball.bounds;
    _btn.layer.cornerRadius = size / 2.0;
}

- (void)applyPrefs {
    if (!_win) return;
    CGFloat size = [self size];
    CGRect f = [self clamped:CGRectMake(_center.x - size / 2, _center.y - size / 2, size, size)];
    _center = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    _win.bounds = CGRectMake(0, 0, size, size);
    [self placeWindowAt:_center];
    [self layoutBall];
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
    CGPoint center = [_ball convertPoint:CGPointMake(CGRectGetMidX(_ball.bounds), CGRectGetMidY(_ball.bounds))
        toView:_win];
    [[RBManager shared] presentFromFloatingWindow:_win center:center];
}

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self hideTemporarily];
}

- (void)panned:(UIPanGestureRecognizer *)g {
    if (!_win) return;
    CGFloat size = [self size];

    CGPoint t = [g translationInView:_win];
    id<UICoordinateSpace> hostSpace = [self hostSpace];
    CGPoint start = [hostSpace convertPoint:CGPointZero fromCoordinateSpace:_win];
    CGPoint end = [hostSpace convertPoint:t fromCoordinateSpace:_win];
    CGRect f = [self clamped:CGRectMake(_center.x - size / 2 + end.x - start.x,
        _center.y - size / 2 + end.y - start.y, size, size)];
    CGRect host = hostSpace.bounds;

    if (g.state == UIGestureRecognizerStateEnded ||
        g.state == UIGestureRecognizerStateCancelled) {
        /* snap flush to a side and dim, like a screen-edge tab */
        if (f.origin.x <= CGRectGetMinX(host) + 24.0) { f.origin.x = CGRectGetMinX(host) + 8.0; _snapped = YES; }
        else if (f.origin.x >= CGRectGetMaxX(host) - size - 24.0) {
            f.origin.x = CGRectGetMaxX(host) - size - 8.0;
            _snapped = YES;
        } else {
            _snapped = NO;
        }
        _ball.alpha = _snapped ? 0.45 : [RBPrefs ballAlpha];
        [RBPrefs setFloatCenter:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f))];
    }

    _center = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    [self placeWindowAt:_center];

    CGPoint zero;
    zero.x = 0.0;
    zero.y = 0.0;
    [g setTranslation:zero inView:_win];
}

@end
