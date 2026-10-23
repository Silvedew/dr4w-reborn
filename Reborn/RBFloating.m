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

    _btn = [UIButton buttonWithType:UIButtonTypeSystem];
    _btn.frame = CGRectMake(0, 0, kSize, kSize);
    _btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    _btn.layer.cornerRadius = kSize / 2.0;
    _btn.layer.borderWidth = 1.0;
    _btn.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.15].CGColor;
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

    CGPoint c = [RBPrefs floatCenter];
    CGFloat half = kSize / 2.0;
    if (c.x < half) c.x = half;
    if (c.y < half) c.y = half;
    if (c.x > root.bounds.size.width - half) c.x = root.bounds.size.width - half;
    if (c.y > root.bounds.size.height - half) c.y = root.bounds.size.height - half;
    _btn.center = c;

    [root addSubview:_btn];
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
    UIView *host = _btn.superview;
    if (!host) return;

    CGPoint t = [g translationInView:host];
    CGPoint c = _btn.center;
    c.x += t.x;
    c.y += t.y;

    CGFloat half = kSize / 2.0;
    if (c.x < half + 8.0) c.x = half + 8.0;
    if (c.y < half + 8.0) c.y = half + 8.0;
    if (c.x > host.bounds.size.width - half - 8.0) c.x = host.bounds.size.width - half - 8.0;
    if (c.y > host.bounds.size.height - half - 8.0) c.y = host.bounds.size.height - half - 8.0;

    _btn.center = c;

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
