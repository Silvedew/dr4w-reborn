#import "RBController.h"
#import "RBManager.h"
#import "RBPrefs.h"
#import "RBFloating.h"
#import "RBChrome.h"
#import "RBIconStyle.h"
#import "RBToolbarLayout.h"
#import "RBWidthPopover.h"

#import "ACEDrawingView.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

static UIImage *RBColorSwatch(UIColor *color, UITraitCollection *traits) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(28, 28)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect circle = CGRectMake(2, 2, 24, 24);
        CGContextSetFillColorWithColor(context.CGContext, color.CGColor);
        CGContextFillEllipseInRect(context.CGContext, circle);
        CGContextSetStrokeColorWithColor(context.CGContext,
            [UIColor.labelColor resolvedColorWithTraitCollection:traits].CGColor);
        CGContextSetLineWidth(context.CGContext, 1);
        CGContextStrokeEllipseInRect(context.CGContext, circle);
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

#pragma mark - quick colour palette (4 circles)

@interface RBColorPaletteVC : UIViewController
@property (nonatomic, strong) NSArray<UIColor *> *colors;
@property (nonatomic, copy) void (^onPick)(UIColor *color);
@property (nonatomic, copy) void (^onMore)(void);
@end

@implementation RBColorPaletteVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    CGFloat size = 44.0;
    CGFloat gap = 8.0;
    CGFloat width = (self.colors.count + 1) * size + (self.colors.count + 2) * gap;
    self.preferredContentSize = CGSizeMake(width, size + gap * 2.0);

    CGFloat x = gap;
    for (NSUInteger i = 0; i < self.colors.count; i++) {
        UIColor *c = self.colors[i];
        UIButton *b = [[RBChromeButton alloc] initWithFrame:CGRectZero];
        b.frame = CGRectMake(x, gap, size, size);
        [b setImage:RBColorSwatch(c, self.traitCollection) forState:UIControlStateNormal];
        b.accessibilityLabel = @[@"黑色", @"红色", @"蓝色", @"绿色"][i];
        b.largeContentTitle = b.accessibilityLabel;
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(pick:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
        x += size + gap;
    }
    UIButton *more = [[RBChromeButton alloc] initWithFrame:CGRectMake(x, gap, size, size)];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightSemibold];
    [more setImage:[UIImage systemImageNamed:@"paintpalette" withConfiguration:config] forState:UIControlStateNormal];
    more.tintColor = UIColor.labelColor;
    more.accessibilityLabel = @"更多颜色";
    more.largeContentTitle = more.accessibilityLabel;
    [more addTarget:self action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:more];
}

- (void)moreTapped:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:self.onMore];
}

- (void)pick:(UIButton *)sender {
    UIColor *c = self.colors[(NSUInteger)sender.tag];
    if (self.onPick) self.onPick(c);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - controller

@interface RBController () <UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate>
@end

@implementation RBController {
    ACEDrawingView *_drawView;
    UIView         *_bar;
    UIScrollView   *_barScroll;
    NSArray<UIButton *> *_barButtons;
    UIButton       *_dragHandle;
    UIPanGestureRecognizer *_barPan;
    RBToolbarPosition _toolbarPosition;
    CGPoint _dragOrigin;

    UIButton       *_color;
    UIButton       *_width;
    UIButton       *_gear;
    UIButton       *_undo;
    UIButton       *_clear;
    UIButton       *_close;

    RBColorPaletteVC *_palette;
    UIColorPickerViewController *_picker;
}

#pragma mark - life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    _toolbarPosition = RBToolbarDefaultPosition();
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
    _dragHandle = [[RBChromeButton alloc] initWithFrame:CGRectZero];
    _dragHandle.accessibilityLabel = @"移动工具栏";
    _dragHandle.accessibilityHint = @"拖动调整位置，或使用上下左右移动辅助操作";
    _dragHandle.largeContentTitle = @"移动工具栏";
    _dragHandle.accessibilityCustomActions = @[
        [[UIAccessibilityCustomAction alloc] initWithName:@"向上移动" target:self selector:@selector(moveToolbarUp:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向下移动" target:self selector:@selector(moveToolbarDown:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向左移动" target:self selector:@selector(moveToolbarLeft:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向右移动" target:self selector:@selector(moveToolbarRight:)]];
    UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(12, 20, 20, 4)];
    grip.backgroundColor = UIColor.secondaryLabelColor;
    grip.layer.cornerRadius = 2;
    grip.userInteractionEnabled = NO;
    [_dragHandle addSubview:grip];
    _barPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragToolbar:)];
    [_dragHandle addGestureRecognizer:_barPan];
    [_bar addSubview:_dragHandle];
    _barScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _barScroll.showsVerticalScrollIndicator = NO;
    _barScroll.showsHorizontalScrollIndicator = NO;
    _barScroll.delaysContentTouches = NO;
    _barScroll.directionalLockEnabled = YES;
    _barScroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _barScroll.layer.cornerRadius = 22;
    _barScroll.layer.cornerCurve = kCACornerCurveContinuous;
    [_bar addSubview:_barScroll];
    _color = [self barButton:@"circle.fill" label:@"画笔颜色" action:@selector(colorTapped:)];
    _width = [self barButton:@"lineweight" label:@"画笔粗细" action:@selector(showWidthsFromButton:)];
    _width.accessibilityValue = [NSString stringWithFormat:@"%.0f 磅", [RBPrefs lineWidth]];
    _gear  = [self barButton:@RB_SETTINGS_SYMBOL label:@"绘图设置" action:@selector(settingsTapped:)];
    _undo  = [self barButton:@"arrow.uturn.backward" label:@"撤销上一笔" action:@selector(undoTapped:)];
    _clear = [self barButton:@"trash" label:@"清空画板" action:@selector(clearTapped:)];
    _close = [self barButton:@"xmark" label:@"关闭画板" action:@selector(closeTapped:)];
    _barButtons = @[_gear, _undo, _clear, _color, _width, _close];
    for (UIButton *button in _barButtons) [_barScroll addSubview:button];

    [self updateColorIcon];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    RBToolbarLayout layout = RBLayoutToolbar(self.view.bounds.size.width, self.view.bounds.size.height,
        insets.top, insets.left, insets.bottom, insets.right, _toolbarPosition);
    _bar.frame = CGRectMake(layout.x, layout.y, layout.width, layout.height);
    _dragHandle.frame = CGRectMake(RBToolbarPadding, RBToolbarPadding, RBToolbarHandle, RBToolbarHandle);
    _barScroll.frame = CGRectMake(0, RBToolbarScrollTop, layout.width,
        MAX(0, layout.height - RBToolbarScrollTop - RBToolbarPadding));
    _barScroll.contentSize = CGSizeMake(RBToolbarThickness, RBToolbarContentLength);
    for (NSUInteger i = 0; i < _barButtons.count; i++) {
        CGFloat position = i * (RBToolbarButton + RBToolbarGap);
        _barButtons[i].frame = CGRectMake(RBToolbarPadding, position, RBToolbarButton, RBToolbarButton);
    }
}

- (void)placeToolbarAt:(CGPoint)origin {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGSize size = self.view.bounds.size;
    RBToolbarLayout minimum = RBLayoutToolbar(size.width, size.height,
        insets.top, insets.left, insets.bottom, insets.right, (RBToolbarPosition){0, 0});
    RBToolbarLayout maximum = RBLayoutToolbar(size.width, size.height,
        insets.top, insets.left, insets.bottom, insets.right, (RBToolbarPosition){1, 1});
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
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    _barPan.enabled = NO;
    _barPan.enabled = YES;
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (BOOL)moveToolbarUp:(UIAccessibilityCustomAction *)action {
    [self placeToolbarAt:CGPointMake(_bar.frame.origin.x, _bar.frame.origin.y - 44)]; return YES;
}
- (BOOL)moveToolbarDown:(UIAccessibilityCustomAction *)action {
    [self placeToolbarAt:CGPointMake(_bar.frame.origin.x, _bar.frame.origin.y + 44)]; return YES;
}
- (BOOL)moveToolbarLeft:(UIAccessibilityCustomAction *)action {
    [self placeToolbarAt:CGPointMake(_bar.frame.origin.x - 44, _bar.frame.origin.y)]; return YES;
}
- (BOOL)moveToolbarRight:(UIAccessibilityCustomAction *)action {
    [self placeToolbarAt:CGPointMake(_bar.frame.origin.x + 44, _bar.frame.origin.y)]; return YES;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.isViewLoaded) [self updateColorIcon];
}

- (void)updateColorIcon {
    [_color setImage:RBColorSwatch([RBPrefs color], self.traitCollection)
            forState:UIControlStateNormal];
    _color.accessibilityValue = @"当前画笔颜色";
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

#pragma mark - colour

- (void)colorTapped:(UIButton *)sender {
    /* palette open -> switch to the full wheel */
    if (_palette) {
        RBColorPaletteVC *p = _palette;
        _palette = nil;
        [p dismissViewControllerAnimated:NO completion:^{
            [self showColorWheel];
        }];
        return;
    }
    if (_picker) {
        [_picker dismissViewControllerAnimated:YES completion:nil];
        _picker = nil;
        return;
    }
    [self showPalette];
}

- (void)showPalette {
    RBColorPaletteVC *vc = [[RBColorPaletteVC alloc] init];
    vc.colors = @[[UIColor colorWithWhite:0.05 alpha:1.0],
                  [UIColor systemRedColor],
                  [UIColor systemBlueColor],
                  [UIColor systemGreenColor]];
    __weak typeof(self) weakSelf = self;
    vc.onPick = ^(UIColor *color) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf applyColor:color];
        strongSelf->_palette = nil;
    };
    vc.onMore = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_palette = nil;
        [strongSelf showColorWheel];
    };
    vc.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController *pop = vc.popoverPresentationController;
    pop.sourceView = _color;
    pop.sourceRect = _color.bounds;
    pop.permittedArrowDirections = UIPopoverArrowDirectionAny;
    pop.backgroundColor = UIColor.secondarySystemBackgroundColor;

    _palette = vc;
    [self presentViewController:vc animated:YES completion:^{
        vc.presentationController.delegate = self;
    }];
}

- (void)showColorWheel {
    UIColorPickerViewController *p = [[UIColorPickerViewController alloc] init];
    p.selectedColor = [RBPrefs color];
    p.supportsAlpha = NO;
    p.delegate = self;
    p.modalPresentationStyle = UIModalPresentationPopover;
    p.preferredContentSize = CGSizeMake(320.0, 420.0);
    UIPopoverPresentationController *pop = p.popoverPresentationController;
    pop.sourceView = _color;
    pop.sourceRect = _color.bounds;
    pop.permittedArrowDirections = UIPopoverArrowDirectionAny;

    _picker = p;
    [self presentViewController:p animated:YES completion:^{
        p.presentationController.delegate = self;
    }];
}

- (void)applyColor:(UIColor *)color {
    [RBPrefs setCustomColor:color];
    _drawView.lineColor = color;
    [self updateColorIcon];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    [self applyColor:viewController.selectedColor];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    _picker = nil;
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if (presentationController.presentedViewController == _palette) _palette = nil;
    if (presentationController.presentedViewController == _picker) _picker = nil;
}

#pragma mark - settings

- (void)anchor:(UIAlertController *)sheet to:(UIView *)view {
    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = view;
        pop.sourceRect = view.bounds;
        pop.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
}

- (void)settingsTapped:(UIButton *)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"绘图设置"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"工具：%@", [RBPrefs toolName]]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self showTools]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"线条颜色"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self colorTapped:nil]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"线条粗细"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self showWidthsFromButton:self->_gear]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"悬浮球大小"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self showBallSize]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"悬浮球透明度"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self showBallAlpha]; }]];
    if (!RBIsSpringBoard()) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"本次使用隐藏圆球"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { [self toggleAppBall]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"一键清屏"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) { [self->_drawView clear]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [self anchor:sheet to:sender];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showTools {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"绘图工具"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *names = [RBPrefs toolNames];
    NSArray<NSNumber *> *types = @[@(ACEDrawingToolTypePen), @(ACEDrawingToolTypeLine),
                                   @(ACEDrawingToolTypeArrow), @(ACEDrawingToolTypeRectagleStroke),
                                   @(ACEDrawingToolTypeRectagleFill), @(ACEDrawingToolTypeEllipseStroke),
                                   @(ACEDrawingToolTypeEllipseFill), @(ACEDrawingToolTypeEraser),
                                   @(ACEDrawingToolTypeDraggableText), @(ACEDrawingToolTypeTriangleStroke),
                                   @(ACEDrawingToolTypePentagonStroke), @(ACEDrawingToolTypeHexagoneStroke)];
    for (NSUInteger i = 0; i < names.count && i < types.count; i++) {
        ACEDrawingToolType t = (ACEDrawingToolType)[types[i] integerValue];
        [sheet addAction:[UIAlertAction actionWithTitle:names[i]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [RBPrefs setTool:t];
            self->_drawView.drawTool = t;
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self anchor:sheet to:_gear];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showBallSize {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"悬浮球大小"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *sizes = @[@44.0, @56.0, @64.0];
    NSArray<NSString *> *names = @[@"小", @"中", @"大"];
    for (NSUInteger i = 0; i < sizes.count; i++) {
        [sheet addAction:[UIAlertAction actionWithTitle:names[i]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [RBPrefs setBallSize:sizes[i].doubleValue];
            [[RBFloating shared] applyPrefs];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self anchor:sheet to:_gear];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showBallAlpha {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"悬浮球透明度"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *values = @[@0.6, @0.8, @1.0];
    NSArray<NSString *> *names = @[@"60%", @"80%", @"100%"];
    for (NSUInteger i = 0; i < values.count; i++) {
        [sheet addAction:[UIAlertAction actionWithTitle:names[i]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [RBPrefs setBallAlpha:values[i].doubleValue];
            [[RBFloating shared] applyPrefs];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self anchor:sheet to:_gear];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)toggleAppBall {
    [[RBFloating shared] hideTemporarily];
}

- (void)showWidthsFromButton:(UIButton *)sender {
    if (self.presentedViewController) {
        [self.presentedViewController dismissViewControllerAnimated:YES completion:^{
            [self showWidthsFromButton:sender];
        }];
        return;
    }
    __weak typeof(self) weakSelf = self;
    RBWidthPopover *popover = [[RBWidthPopover alloc] initWithWidth:_drawView.lineWidth change:^(CGFloat width) {
        __strong typeof(weakSelf) controller = weakSelf;
        if (!controller) return;
        controller->_drawView.lineWidth = width;
        controller->_width.accessibilityValue = [NSString stringWithFormat:@"%.0f 磅", width];
    } commit:^(CGFloat width) { [RBPrefs setLineWidth:width]; }];
    popover.popoverPresentationController.sourceView = sender;
    popover.popoverPresentationController.sourceRect = sender.bounds;
    popover.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    [self presentViewController:popover animated:YES completion:nil];
}

@end
