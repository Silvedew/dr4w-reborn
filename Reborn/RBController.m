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

    UIButton       *_brush;
    UIButton       *_gear;
    UIButton       *_undo;
    UIButton       *_clear;
    UIButton       *_close;
    RBBrushPopover *_brushPanel;
    UIControl      *_brushDismissArea;
    __weak UIButton *_brushAnchor;
    RBSettingsPanel *_settingsPanel;
    UIControl *_settingsDismissArea;
    CGRect _keyboardScreenFrame;

}

#pragma mark - life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    _toolbarPosition = RBToolbarPositionForApp(NSBundle.mainBundle.bundleIdentifier);
    _toolbarScale = [RBPrefs toolbarScale];
    self.view.backgroundColor = [UIColor clearColor];

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
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

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
    _gear  = [self barButton:@RB_SETTINGS_SYMBOL label:@"绘图设置" action:@selector(settingsTapped:)];
    _gear.accessibilityHint = @"单指拖动工具栏，双指滚动按钮；辅助操作可移动工具栏";
    _gear.accessibilityCustomActions = @[
        [[UIAccessibilityCustomAction alloc] initWithName:@"向上移动工具栏" target:self selector:@selector(moveToolbarUp:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向下移动工具栏" target:self selector:@selector(moveToolbarDown:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向左移动工具栏" target:self selector:@selector(moveToolbarLeft:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向右移动工具栏" target:self selector:@selector(moveToolbarRight:)]];
    _undo  = [self barButton:@"arrow.uturn.backward" label:@"撤销上一笔" action:@selector(undoTapped:)];
    _clear = [self barButton:@"trash" label:@"清空画板" action:@selector(clearTapped:)];
    _close = [self barButton:@"xmark" label:@"关闭画板" action:@selector(closeTapped:)];
    _barButtons = @[_close, _clear, _brush, _undo, _gear];
    for (UIButton *button in _barButtons) [_barScroll addSubview:button];

}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    RBToolbarMetrics metrics = RBToolbarMetricsForScale(_toolbarScale);
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
    if (gesture.state == UIGestureRecognizerStateEnded) [self saveToolbarPosition];
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
[self placeToolbarAt:CGPointMake(_bar.frame.origin.x, _bar.frame.origin.y - 44)]; [self saveToolbarPosition]; return YES;
}
- (BOOL)moveToolbarDown:(UIAccessibilityCustomAction *)action {
[self placeToolbarAt:CGPointMake(_bar.frame.origin.x, _bar.frame.origin.y + 44)]; [self saveToolbarPosition]; return YES;
}
- (BOOL)moveToolbarLeft:(UIAccessibilityCustomAction *)action {
[self placeToolbarAt:CGPointMake(_bar.frame.origin.x - 44, _bar.frame.origin.y)]; [self saveToolbarPosition]; return YES;
}
- (BOOL)moveToolbarRight:(UIAccessibilityCustomAction *)action {
[self placeToolbarAt:CGPointMake(_bar.frame.origin.x + 44, _bar.frame.origin.y)]; [self saveToolbarPosition]; return YES;
}


#pragma mark - actions

- (void)undoTapped:(UIButton *)sender {
    [_drawView undoLatestStep];
}

- (void)clearTapped:(UIButton *)sender {
    [_drawView clear];
}

- (void)closeTapped:(UIButton *)sender {
    [[RBManager shared] dismiss];
}


#pragma mark - settings

- (void)settingsTapped:(UIButton *)sender {
    if (_settingsPanel) return;
    [self closeBrushPanel];
    _settingsPanel = [RBSettingsPanel new];
    _settingsPanel.toolbarScale = _toolbarScale;
    __weak typeof(self) weakSelf = self;
    _settingsPanel.closeHandler = ^{ [weakSelf closeSettingsPanel]; };
    _settingsPanel.brushHandler = ^{
        RBController *controller = weakSelf;
        if (!controller) return;
        [controller closeSettingsPanel];
        [controller showBrushFromButton:controller->_gear];
    };
    _settingsPanel.clearHandler = ^{
        RBController *controller = weakSelf;
        if (controller) [controller->_drawView clear];
    };
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
