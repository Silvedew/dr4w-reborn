#import "RBController.h"
#import "RBManager.h"
#import "RBPrefs.h"
#import "RBFloating.h"
#import "RBChrome.h"
#import "RBIconStyle.h"
#import "RBToolbarLayout.h"
#import "RBBrushPopover.h"
#import "RBSettingsPanel.h"
#import "RBSettingsPanelLayout.h"
#import "RBBrushLayout.h"
#import "RBSettings.h"
#import "RBScreenshotPolicy.h"

#import "ACEDrawingView.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface RBToolbarScrollView : UIScrollView
@end

@implementation RBToolbarScrollView
- (BOOL)touchesShouldCancelInContentView:(UIView *)view { return YES; }
@end


#pragma mark - controller


@implementation RBController {
    ACEDrawingView *_drawView;
    UIView         *_bar;
    UIScrollView   *_barScroll;
    NSArray<UIButton *> *_barButtons;
    UIPanGestureRecognizer *_barPan;
    RBToolbarPosition _toolbarPosition;
    CGFloat _toolbarScale;
    BOOL _previewingToolbarScale;
    CGPoint _dragOrigin;
    BOOL _toolbarWasMoved;
    UIWindow *_initialToolbarAnchorWindow;
    CGPoint _initialToolbarAnchor;

    UIButton       *_brush;
    UIButton       *_gear;
    UIButton       *_undo;
    UIButton       *_clear;
    UIButton       *_close;
    UIButton       *_screenshot;
    RBBrushPopover *_brushPanel;
    UIControl      *_brushDismissArea;
    __weak UIButton *_brushAnchor;
    RBSettingsPanel *_settingsPanel;
    UIControl *_settingsDismissArea;
    CGRect _keyboardScreenFrame;
    BOOL _keyboardTransitioning;
    RBScreenshotSession _screenshotSession;
    NSTimeInterval _screenshotDeadline;
    BOOL _screenshotWaitingForKeyboard;
    BOOL _screenshotDrawingInteraction;
    CADisplayLink *_screenshotDisplayLink;
    NSUInteger _screenshotFrames;
    NSArray<UIView *> *_screenshotChrome;
    NSArray<NSNumber *> *_screenshotChromeHidden;
    UILabel *_screenshotMessage;

}

#pragma mark - life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    _toolbarPosition = RBToolbarPositionForApp(NSBundle.mainBundle.bundleIdentifier);
    _toolbarScale = [RBPrefs toolbarScale];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.opaque = NO;

    _drawView = [[ACEDrawingView alloc] initWithFrame:self.view.bounds];
    _drawView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _drawView.backgroundColor = [UIColor clearColor];
    _drawView.clipsToBounds = YES;
    _drawView.drawTool = [RBPrefs tool];
    _drawView.lineColor = [RBPrefs color];
    _drawView.lineWidth = [RBPrefs lineWidth];
    _drawView.lineAlpha = 1.0;
    _drawView.draggableTextCloseImage = [UIImage systemImageNamed:@"xmark.circle.fill"];
    _drawView.draggableTextRotateImage = [UIImage systemImageNamed:@"arrow.clockwise.circle.fill"];
    [self.view addSubview:_drawView];

    [self buildBar];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:)
        name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:)
        name:UIKeyboardWillHideNotification object:nil];
    for (NSNotificationName name in @[UIKeyboardDidHideNotification, UIKeyboardDidChangeFrameNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenshotKeyboardSettled:)
            name:name object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(systemScreenshotTaken:)
        name:UIApplicationUserDidTakeScreenshotNotification object:nil];
    for (NSNotificationName name in @[UIApplicationWillResignActiveNotification,
        UISceneWillDeactivateNotification, UISceneDidDisconnectNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenshotHostDidDeactivate:)
            name:name object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Keep the source anchor through the window's first safe-area layouts.
    [self.view layoutIfNeeded];
    _initialToolbarAnchorWindow = nil;
}

#pragma mark - toolbar

- (UIButton *)barButton:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *b = [[RBChromeButton alloc] initWithFrame:CGRectZero];
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:21.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:symbol];
    [b setImage:img forState:UIControlStateNormal];
    b.accessibilityLabel = label;
    b.largeContentTitle = label;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildBar {
    _bar = [[RBChromeSurface alloc] initWithFrame:CGRectZero];
    [self.view addSubview:_bar];
    _barPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragToolbar:)];
    _barPan.maximumNumberOfTouches = 1;
    _barPan.cancelsTouchesInView = YES;
    [_bar addGestureRecognizer:_barPan];
    _barScroll = [[RBToolbarScrollView alloc] initWithFrame:CGRectZero];
    _barScroll.showsVerticalScrollIndicator = NO;
    _barScroll.showsHorizontalScrollIndicator = NO;
    _barScroll.delaysContentTouches = NO;
    _barScroll.canCancelContentTouches = YES;
    _barScroll.panGestureRecognizer.minimumNumberOfTouches = 2;
    _barScroll.panGestureRecognizer.maximumNumberOfTouches = 2;
    _barScroll.directionalLockEnabled = YES;
    _barScroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _barScroll.layer.cornerRadius = 22;
    _barScroll.layer.cornerCurve = kCACornerCurveContinuous;
    [_bar addSubview:_barScroll];
    _brush = [self barButton:@RB_PENCIL_SYMBOL label:@"画笔设置" action:@selector(showBrushFromButton:)];
    _brush.accessibilityValue = [NSString stringWithFormat:@"粗细 %.0f 磅", [RBPrefs lineWidth]];
    _gear  = [self barButton:@RB_SETTINGS_SYMBOL label:@"设置" action:@selector(settingsTapped:)];
    _gear.accessibilityHint = @"单指拖动工具栏，双指滚动按钮；辅助操作可移动工具栏";
    _gear.accessibilityCustomActions = @[
        [[UIAccessibilityCustomAction alloc] initWithName:@"向上移动工具栏" target:self selector:@selector(moveToolbarUp:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向下移动工具栏" target:self selector:@selector(moveToolbarDown:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向左移动工具栏" target:self selector:@selector(moveToolbarLeft:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向右移动工具栏" target:self selector:@selector(moveToolbarRight:)]];
    _undo  = [self barButton:@"arrow.uturn.backward" label:@"撤销上一笔" action:@selector(undoTapped:)];
    _clear = [self barButton:@"trash" label:@"清空画板" action:@selector(clearTapped:)];
    _close = [self barButton:@"xmark" label:@"关闭画板" action:@selector(closeTapped:)];
    _screenshot = [self barButton:@"camera" label:@"保存系统截图" action:@selector(screenshotTapped:)];
    _screenshot.accessibilityHint = @"隐藏工具栏后保存带标注的系统截图，成功后关闭画板";
    _barButtons = @[_close, _clear, _brush, _undo, _screenshot, _gear];
    for (UIButton *button in _barButtons) [_barScroll addSubview:button];

}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    RBToolbarMetrics metrics = RBToolbarMetricsForScale(_toolbarScale);
    if (_initialToolbarAnchorWindow && self.view.window) {
        CGPoint anchor = [self.view convertPoint:_initialToolbarAnchor fromCoordinateSpace:_initialToolbarAnchorWindow];
        CGSize size = self.view.bounds.size;
        RBToolbarLayout minimum = RBLayoutToolbar(size.width, size.height,
            insets.top, insets.left, insets.bottom, insets.right, (RBToolbarPosition){0, 0}, _toolbarScale);
        RBToolbarLayout maximum = RBLayoutToolbar(size.width, size.height,
            insets.top, insets.left, insets.bottom, insets.right, (RBToolbarPosition){1, 1}, _toolbarScale);
        _toolbarPosition = RBToolbarPositionForTopAnchor(minimum, maximum,
            (RBToolbarPoint){anchor.x, anchor.y}, _toolbarPosition, _toolbarScale);
    }
    RBToolbarLayout layout = RBLayoutToolbar(self.view.bounds.size.width, self.view.bounds.size.height,
        insets.top, insets.left, insets.bottom, insets.right, _toolbarPosition, _toolbarScale);
    _bar.frame = CGRectMake(layout.x, layout.y, layout.width, layout.height);
    _bar.layer.cornerRadius = 22 * _toolbarScale;
    _barScroll.layer.cornerRadius = 22 * _toolbarScale;
    _barScroll.frame = CGRectMake(0, metrics.padding, layout.width,
        MAX(0, layout.height - 2 * metrics.padding));
    _barScroll.contentSize = CGSizeMake(layout.width, metrics.contentLength);
    CGFloat maximumOffset = MAX(0, metrics.contentLength - _barScroll.bounds.size.height);
    _barScroll.contentOffset = CGPointMake(0, MIN(MAX(0, _barScroll.contentOffset.y), maximumOffset));
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration
        configurationWithPointSize:metrics.icon weight:UIImageSymbolWeightSemibold];
    for (NSUInteger i = 0; i < _barButtons.count; i++) {
        UIButton *button = _barButtons[i];
        CGFloat position = i * (metrics.button + metrics.gap);
        button.frame = CGRectMake((layout.width - metrics.button) / 2, position, metrics.button, metrics.button);
        button.layer.cornerRadius = 14 * _toolbarScale;
        [button setPreferredSymbolConfiguration:configuration forImageInState:UIControlStateNormal];
    }
    [self layoutBrushPanel];
    [self layoutSettingsPanel];
}

- (void)preferredContentSizeDidChangeForChildContentContainer:(id<UIContentContainer>)container {
    [super preferredContentSizeDidChangeForChildContentContainer:container];
    if (container == _settingsPanel) [self.view setNeedsLayout];
}

- (void)setInitialToolbarAnchor:(CGPoint)anchor fromWindow:(UIWindow *)sourceWindow {
    if (!isfinite(anchor.x) || !isfinite(anchor.y)) return;
    _initialToolbarAnchor = anchor;
    _initialToolbarAnchorWindow = sourceWindow;
}

- (void)syncFloatingPositionAfterUserClose {
    if (!_toolbarWasMoved || !self.view.window) return;
    [self.view layoutIfNeeded];
    CGRect frame = _bar.frame;
    RBToolbarPoint anchor = RBToolbarTopAnchor((RBToolbarLayout){frame.origin.x, frame.origin.y,
        frame.size.width, frame.size.height}, _toolbarScale);
    CGPoint point = [self.view convertPoint:CGPointMake(anchor.x, anchor.y) toView:self.view.window];
    [[RBFloating shared] updatePosition:point fromWindow:self.view.window];
}

- (void)previewToolbarScale:(CGFloat)scale {
    _toolbarScale = RBToolbarScale(scale);
    if (!self.isViewLoaded) return;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)commitToolbarScale:(CGFloat)scale {
    [RBPrefs setToolbarScale:RBToolbarScale(scale)];
    [self previewToolbarScale:scale];
}

- (void)refreshToolbarPreferences {
    if (!_previewingToolbarScale) {
        [self previewToolbarScale:[RBPrefs toolbarScale]];
        _settingsPanel.toolbarScale = _toolbarScale;
    }
    [_settingsPanel refreshApplicationStates];
}

- (void)layoutBrushPanel {
    if (!_brushPanel) return;
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGRect anchor = [_brushAnchor convertRect:_brushAnchor.bounds toView:self.view];
    RBBrushFrame frame = RBBrushFrameForHost(safe.origin.x, safe.origin.y,
        safe.size.width, safe.size.height, _bar.frame.origin.x, _bar.frame.size.width, CGRectGetMidY(anchor));
    [_brushPanel updateAvailableSize:safe.size];
    _brushDismissArea.frame = self.view.bounds;
    _brushPanel.view.frame = CGRectMake(frame.x, frame.y, frame.width, frame.height);
}

- (void)placeToolbarAt:(CGPoint)origin {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGSize size = self.view.bounds.size;
    RBToolbarLayout minimum = RBLayoutToolbar(size.width, size.height,
        insets.top, insets.left, insets.bottom, insets.right, (RBToolbarPosition){0, 0}, _toolbarScale);
    RBToolbarLayout maximum = RBLayoutToolbar(size.width, size.height,
        insets.top, insets.left, insets.bottom, insets.right, (RBToolbarPosition){1, 1}, _toolbarScale);
    _toolbarPosition = RBToolbarPositionForOrigin(minimum, maximum, origin.x, origin.y, _toolbarPosition);
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)dragToolbar:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) _dragOrigin = _bar.frame.origin;
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged ||
        gesture.state == UIGestureRecognizerStateEnded) {
        CGPoint translation = [gesture translationInView:self.view];
        [self placeToolbarAt:CGPointMake(_dragOrigin.x + translation.x, _dragOrigin.y + translation.y)];
    }
    if (gesture.state == UIGestureRecognizerStateEnded) [self finishToolbarMoveFrom:_dragOrigin];
}

- (void)finishToolbarMoveFrom:(CGPoint)origin {
    CGPoint current = _bar.frame.origin;
    if (!RBToolbarPointsDiffer((RBToolbarPoint){origin.x, origin.y}, (RBToolbarPoint){current.x, current.y})) return;
    _toolbarWasMoved = YES;
    [self saveToolbarPosition];
}

- (void)saveToolbarPosition {
    RBSaveToolbarPosition(NSBundle.mainBundle.bundleIdentifier, _toolbarPosition);
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    _barPan.enabled = NO;
    _barPan.enabled = YES;
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (BOOL)moveToolbarUp:(UIAccessibilityCustomAction *)action {
    return [self moveToolbarBy:CGPointMake(0, -44)];
}
- (BOOL)moveToolbarDown:(UIAccessibilityCustomAction *)action {
    return [self moveToolbarBy:CGPointMake(0, 44)];
}
- (BOOL)moveToolbarLeft:(UIAccessibilityCustomAction *)action {
    return [self moveToolbarBy:CGPointMake(-44, 0)];
}
- (BOOL)moveToolbarRight:(UIAccessibilityCustomAction *)action {
    return [self moveToolbarBy:CGPointMake(44, 0)];
}

- (BOOL)moveToolbarBy:(CGPoint)translation {
    CGPoint origin = _bar.frame.origin;
    [self placeToolbarAt:CGPointMake(origin.x + translation.x, origin.y + translation.y)];
    [self finishToolbarMoveFrom:origin];
    return YES;
}


#pragma mark - actions

- (void)undoTapped:(UIButton *)sender {
    [_drawView undoLatestStep];
}

- (void)clearTapped:(UIButton *)sender {
    [_drawView clear];
}

- (void)closeTapped:(UIButton *)sender {
    [[RBManager shared] dismissFromUser];
}

- (BOOL)screenshotSessionIsCurrent:(uint64_t)generation {
    return RBScreenshotIsCurrent(&_screenshotSession, generation) &&
        [[RBManager shared] isActiveDrawingController:self];
}

- (BOOL)screenshotKeyboardIsVisible {
    if (CGRectIsEmpty(_keyboardScreenFrame)) return NO;
    CGRect screen = self.view.window.screen.coordinateSpace.bounds;
    CGRect overlap = CGRectIntersection(screen, _keyboardScreenFrame);
    return !CGRectIsNull(overlap) && !CGRectIsEmpty(overlap);
}

- (void)screenshotTapped:(UIButton *)sender {
    if (![[RBManager shared] isActiveDrawingController:self] || !RBScreenshotBegin(&_screenshotSession)) return;
    uint64_t generation = _screenshotSession.generation;
    _screenshotDeadline = NSProcessInfo.processInfo.systemUptime + 3.0;
    [_screenshotMessage removeFromSuperview];
    _screenshotMessage = nil;
    NSMutableArray *chrome = [NSMutableArray arrayWithObject:_bar];
    if (_brushPanel) [chrome addObjectsFromArray:@[_brushPanel.view, _brushDismissArea]];
    if (_settingsPanel) [chrome addObjectsFromArray:@[_settingsPanel.view, _settingsDismissArea]];
    _screenshotChrome = chrome;
    NSMutableArray *hidden = [NSMutableArray array];
    for (UIView *view in chrome) {
        [hidden addObject:@(view.hidden)];
        view.hidden = YES;
    }
    _screenshotChromeHidden = hidden;
    _screenshotDrawingInteraction = _drawView.userInteractionEnabled;
    _drawView.userInteractionEnabled = NO;
    // Set this before reloadInputViews, whose keyboard notifications can be synchronous.
    _screenshotWaitingForKeyboard = YES;
    [_drawView beginSystemScreenshot];
    _screenshotWaitingForKeyboard = _keyboardTransitioning || [self screenshotKeyboardIsVisible];
    if (!_screenshotWaitingForKeyboard) [self waitForScreenshotFrames];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        RBController *controller = weakSelf;
        if ([controller screenshotSessionIsCurrent:generation])
            [controller finishScreenshot:RBScreenshotExpired(&controller->_screenshotSession)];
    });
}

- (void)screenshotKeyboardSettled:(NSNotification *)notification {
    _keyboardTransitioning = NO;
    _keyboardScreenFrame = [notification.name isEqual:UIKeyboardDidHideNotification] ? CGRectZero :
        [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (_screenshotSession.active && _screenshotWaitingForKeyboard && ![self screenshotKeyboardIsVisible]) {
        _screenshotWaitingForKeyboard = NO;
        [self waitForScreenshotFrames];
    }
}

- (void)waitForScreenshotFrames {
    if (_screenshotDisplayLink || !_screenshotSession.active || _screenshotSession.sent) return;
    [self.view layoutIfNeeded];
    _screenshotFrames = 0;
    _screenshotDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(screenshotFrame:)];
    [_screenshotDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)screenshotFrame:(CADisplayLink *)displayLink {
    if (![self screenshotSessionIsCurrent:_screenshotSession.generation]) {
        [self cancelPendingScreenshot];
        return;
    }
    // The first callback precedes presentation; the next guarantees a full hidden-chrome frame.
    if (++_screenshotFrames < 2) return;
    [displayLink invalidate];
    _screenshotDisplayLink = nil;
    if (NSProcessInfo.processInfo.systemUptime >= _screenshotDeadline) {
        [self finishScreenshot:RBScreenshotRejected];
        return;
    }
    uint64_t generation = _screenshotSession.generation;
    __weak typeof(self) weakSelf = self;
    [[RBManager shared] requestScreenshotForController:self deadline:_screenshotDeadline
        willSend:^BOOL {
            RBController *controller = weakSelf;
            if (![controller screenshotSessionIsCurrent:generation]) return NO;
            controller->_screenshotSession.sent = true;
            return YES;
        }
        completion:^(RBScreenshotResult reply) {
            RBController *controller = weakSelf;
            if (![controller screenshotSessionIsCurrent:generation]) return;
            RBScreenshotResult result = RBScreenshotAcknowledge(&controller->_screenshotSession, reply);
            if (result != RBScreenshotPending) [controller finishScreenshot:result];
        }];
}

- (void)systemScreenshotTaken:(NSNotification *)notification {
    if (![self screenshotSessionIsCurrent:_screenshotSession.generation]) return;
    // UIKit exposes no request identifier; a simultaneous hardware screenshot cannot be distinguished.
    RBScreenshotResult result = RBScreenshotObserved(&_screenshotSession);
    if (result == RBScreenshotSucceeded) [self finishScreenshot:result];
}

- (void)restoreScreenshotPresentationWithFocus:(BOOL)restoreFocus {
    [_screenshotDisplayLink invalidate];
    _screenshotDisplayLink = nil;
    _screenshotWaitingForKeyboard = NO;
    for (NSUInteger i = 0; i < _screenshotChrome.count; i++)
        _screenshotChrome[i].hidden = _screenshotChromeHidden[i].boolValue;
    _screenshotChrome = nil;
    _screenshotChromeHidden = nil;
    [_drawView endSystemScreenshotRestoringFocus:restoreFocus];
    _drawView.userInteractionEnabled = _screenshotDrawingInteraction;
}

- (void)cancelPendingScreenshot {
    if (!_screenshotSession.active) return;
    RBScreenshotCancel(&_screenshotSession);
    [self restoreScreenshotPresentationWithFocus:NO];
}

- (void)screenshotHostDidDeactivate:(NSNotification *)notification {
    if ([notification.name isEqualToString:UIApplicationWillResignActiveNotification] ||
        notification.object == self.view.window.windowScene) [self cancelPendingScreenshot];
}

- (void)finishScreenshot:(RBScreenshotResult)result {
    if (![self screenshotSessionIsCurrent:_screenshotSession.generation]) return;
    RBScreenshotCancel(&_screenshotSession);
    if (result == RBScreenshotSucceeded) {
        [self restoreScreenshotPresentationWithFocus:NO];
        [[RBManager shared] dismissFromUser];
        return;
    }
    [self restoreScreenshotPresentationWithFocus:YES];
    NSString *message = result == RBScreenshotUncertain ? @"截图状态不确定，请查看系统截图后再操作" :
        @"系统截图未完成，画板已恢复";
    // A nonmodal notice preserves the text field's focus and marked text after a failed capture.
    UILabel *notice = [[UILabel alloc] initWithFrame:CGRectZero];
    notice.text = message;
    notice.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    notice.textColor = UIColor.labelColor;
    notice.backgroundColor = UIColor.secondarySystemBackgroundColor;
    notice.textAlignment = NSTextAlignmentCenter;
    notice.numberOfLines = 0;
    notice.layer.cornerRadius = 12;
    notice.clipsToBounds = YES;
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    notice.frame = CGRectMake(CGRectGetMinX(safe) + 16, CGRectGetMinY(safe) + 12, MAX(0, safe.size.width - 32), 64);
    _screenshotMessage = notice;
    [self.view addSubview:notice];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [notice removeFromSuperview];
    });
}


#pragma mark - settings

- (void)settingsTapped:(UIButton *)sender {
    if (_settingsPanel) return;
    [self closeBrushPanel];
    _settingsPanel = [RBSettingsPanel new];
    _settingsPanel.toolbarScale = _toolbarScale;
    __weak typeof(self) weakSelf = self;
    _settingsPanel.closeHandler = ^{ [weakSelf closeSettingsPanel]; };
    _settingsPanel.hideBallHandler = ^{ [[RBFloating shared] hideTemporarily]; };
    _settingsPanel.toolChange = ^(ACEDrawingToolType tool) {
        RBController *controller = weakSelf;
        if (controller) controller->_drawView.drawTool = tool;
    };
    _settingsPanel.toolbarScaleChange = ^(CGFloat scale) {
        RBController *controller = weakSelf;
        if (!controller) return;
        controller->_previewingToolbarScale = YES;
        [controller previewToolbarScale:scale];
    };
    _settingsPanel.toolbarScaleCommit = ^(CGFloat scale) {
        RBController *controller = weakSelf;
        if (!controller) return;
        controller->_previewingToolbarScale = NO;
        [controller commitToolbarScale:scale];
    };
    _settingsDismissArea = [[UIControl alloc] initWithFrame:self.view.bounds];
    _settingsDismissArea.backgroundColor = UIColor.clearColor;
    _settingsDismissArea.opaque = NO;
    [_settingsDismissArea addTarget:self action:@selector(closeSettingsPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_settingsDismissArea];
    [self addChildViewController:_settingsPanel];
    [self layoutSettingsPanel];
    [self.view addSubview:_settingsPanel.view];
    [_settingsPanel didMoveToParentViewController:self];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _settingsPanel.view);
}

- (void)keyboardChanged:(NSNotification *)notification {
    _keyboardTransitioning = YES;
    _keyboardScreenFrame = [notification.name isEqualToString:UIKeyboardWillHideNotification]
        ? CGRectZero : [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    [self layoutSettingsPanel];
}

- (void)layoutSettingsPanel {
    if (!_settingsPanel) return;
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    if (!CGRectIsEmpty(_keyboardScreenFrame) && self.view.window) {
        CGRect keyboard = [self.view convertRect:_keyboardScreenFrame
            fromCoordinateSpace:self.view.window.screen.coordinateSpace];
        CGRect intersection = CGRectIntersection(safe, keyboard);
        if (!CGRectIsNull(intersection) && !CGRectIsEmpty(intersection)) {
            RBSettingsPanelHost available = RBSettingsPanelHostAvoidingKeyboard(
                (RBSettingsPanelHost){safe.origin.x, safe.origin.y, safe.size.width, safe.size.height},
                (RBSettingsPanelHost){keyboard.origin.x, keyboard.origin.y, keyboard.size.width, keyboard.size.height});
            safe = CGRectMake(available.x, available.y, available.width, available.height);
        }
    }
    [_settingsPanel updateAvailableSize:safe.size];
    CGSize size = _settingsPanel.preferredContentSize;
    CGRect anchor = [_gear convertRect:_gear.bounds toView:self.view];
    BOOL right = CGRectGetMidX(_bar.frame) < CGRectGetMidX(safe);
    CGFloat x = right ? CGRectGetMaxX(_bar.frame) + 8 : CGRectGetMinX(_bar.frame) - 8 - size.width;
    x = RBBrushClampOrigin(x, CGRectGetMinX(safe) + 12, CGRectGetMaxX(safe) - 12 - size.width);
    CGFloat y = RBBrushClampOrigin(CGRectGetMidY(anchor) - size.height / 2,
        CGRectGetMinY(safe) + 12, CGRectGetMaxY(safe) - 12 - size.height);
    _settingsDismissArea.frame = self.view.bounds;
    _settingsPanel.view.frame = CGRectMake(x, y, size.width, size.height);
}

- (void)closeSettingsPanel {
    if (!_settingsPanel) return;
    [_settingsPanel commitPendingChanges];
    [_settingsPanel.view endEditing:YES];
    [_settingsPanel willMoveToParentViewController:nil];
    [_settingsPanel.view removeFromSuperview];
    [_settingsPanel removeFromParentViewController];
    [_settingsDismissArea removeFromSuperview];
    _settingsPanel = nil;
    _settingsDismissArea = nil;
    _keyboardScreenFrame = CGRectZero;
    if (self.view.window && !self.view.window.hidden)
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _gear);
}

- (void)showBrushFromButton:(UIButton *)sender {
    if (_brushPanel) return;
    [self closeSettingsPanel];
    if (self.presentedViewController) {
        [self.presentedViewController dismissViewControllerAnimated:YES completion:^{
            [self showBrushFromButton:sender];
        }];
        return;
    }
    __weak typeof(self) weakSelf = self;
    _brushPanel = [[RBBrushPopover alloc] initWithColor:_drawView.lineColor
        width:_drawView.lineWidth colorChange:^(UIColor *color) {
            __strong typeof(weakSelf) controller = weakSelf;
            if (!controller) return;
            controller->_drawView.lineColor = color;
        } widthChange:^(CGFloat width) {
            __strong typeof(weakSelf) controller = weakSelf;
            if (!controller) return;
            controller->_drawView.lineWidth = width;
            controller->_brush.accessibilityValue = [NSString stringWithFormat:@"粗细 %.0f 磅", width];
        } widthCommit:^(CGFloat width) { [RBPrefs setLineWidth:width]; }];
    _brushPanel.closeHandler = ^{ [weakSelf closeBrushPanel]; };
    _brushAnchor = sender;
    _brushDismissArea = [[UIControl alloc] initWithFrame:self.view.bounds];
    _brushDismissArea.backgroundColor = UIColor.clearColor;
    _brushDismissArea.opaque = NO;
    [_brushDismissArea addTarget:self action:@selector(closeBrushPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_brushDismissArea];
    [self addChildViewController:_brushPanel];
    [self layoutBrushPanel];
    [self.view addSubview:_brushPanel.view];
    [_brushPanel didMoveToParentViewController:self];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _brushPanel.view);
}

- (void)closeBrushPanel {
    if (!_brushPanel) return;
    [_brushPanel commitPendingChanges];
    if (_brushPanel.presentedViewController)
        [_brushPanel dismissViewControllerAnimated:NO completion:nil];
    [_brushPanel willMoveToParentViewController:nil];
    [_brushPanel.view removeFromSuperview];
    [_brushPanel removeFromParentViewController];
    [_brushDismissArea removeFromSuperview];
    UIButton *anchor = _brushAnchor ?: _brush;
    _brushPanel = nil;
    _brushDismissArea = nil;
    _brushAnchor = nil;
    if (self.view.window && !self.view.window.hidden)
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, anchor);
}

@end
