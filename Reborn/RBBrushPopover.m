#import "RBBrushPopover.h"
#import "RBChrome.h"
#import "RBWidthPopover.h"
#import "RBBrushLayout.h"
#import "RBSettings.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

// Replace UIKit's popover material so the toolbar chrome is the only background.
@interface RBBrushBackgroundView : UIPopoverBackgroundView
@property (nonatomic) CGFloat arrowOffset;
@property (nonatomic) UIPopoverArrowDirection arrowDirection;
@end
@implementation RBBrushBackgroundView {
    RBChromeSurface *_surface;
}
@synthesize arrowOffset = _arrowOffset;
@synthesize arrowDirection = _arrowDirection;
+ (CGFloat)arrowBase { return 0; }
+ (CGFloat)arrowHeight { return 0; }
+ (UIEdgeInsets)contentViewInsets { return UIEdgeInsetsZero; }
+ (BOOL)wantsDefaultContentAppearance { return NO; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        _surface = [[RBChromeSurface alloc] initWithFrame:self.bounds];
        _surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_surface];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.shadowOpacity = 0;
    _surface.frame = self.bounds;
}
@end

@interface RBBrushPopover () <UIColorPickerViewControllerDelegate, UIPopoverPresentationControllerDelegate>
@end

@implementation RBBrushPopover {
    UIColor *_color;
    void (^_colorChange)(UIColor *);
    RBWidthPopover *_widthController;
    UIScrollView *_scroll;
    UIButton *_close;
    NSMutableArray<UIColor *> *_colors;
    NSArray<UIButton *> *_buttons;
    NSInteger _selectedSlot;
    BOOL _colorDirty;
    UIColorPickerViewController *_picker;
    CGSize _availableSize;
}
- (instancetype)initWithColor:(UIColor *)color width:(CGFloat)width
    colorChange:(void (^)(UIColor *))colorChange widthChange:(void (^)(CGFloat))widthChange
    widthCommit:(void (^)(CGFloat))widthCommit {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _color = color;
        _colorChange = [colorChange copy];
        _colors = [@[[UIColor colorWithWhite:0.05 alpha:1], UIColor.systemRedColor,
            UIColor.systemBlueColor, UIColor.systemGreenColor] mutableCopy];
        for (NSUInteger i = 0; i < RBBrushColorCount; i++) {
            NSArray *rgba = RBBrushColorForSlot(i);
            if (rgba) _colors[i] = [UIColor colorWithRed:[rgba[0] doubleValue] green:[rgba[1] doubleValue]
                blue:[rgba[2] doubleValue] alpha:[rgba[3] doubleValue]];
        }
        NSInteger saved = RBSelectedBrushSlot();
        _selectedSlot = saved >= 0 && [self matchesColor:_colors[saved]] ? saved : -1;
        if (_selectedSlot < 0) {
            for (NSUInteger i = 0; i < RBBrushColorCount; i++) {
                if ([self matchesColor:_colors[i]]) { _selectedSlot = i; break; }
            }
        }
        _widthController = [[RBWidthPopover alloc] initWithWidth:width change:widthChange commit:widthCommit];
        self.preferredContentSize = CGSizeMake(RBBrushWidth, RBBrushHeight);
        self.modalPresentationStyle = UIModalPresentationPopover;
        self.popoverPresentationController.delegate = self;
        self.popoverPresentationController.backgroundColor = UIColor.clearColor;
        self.popoverPresentationController.popoverBackgroundViewClass = RBBrushBackgroundView.class;
        self.popoverPresentationController.popoverLayoutMargins = UIEdgeInsetsMake(8, 8, 8, 8);
    }
    return self;
}
- (void)updateAvailableSize:(CGSize)size {
    _availableSize = size;
    RBBrushSize panel = RBBrushSizeForHost(size.width, size.height);
    CGSize preferred = CGSizeMake(panel.width, panel.height);
    if (!CGSizeEqualToSize(preferred, self.preferredContentSize)) self.preferredContentSize = preferred;
    CGSize pickerSize = CGSizeMake(MIN(320, MAX(0, size.width - 24)), MIN(420, MAX(0, size.height - 24)));
    if (_picker && !CGSizeEqualToSize(pickerSize, _picker.preferredContentSize)) _picker.preferredContentSize = pickerSize;
}
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller {
    return UIModalPresentationNone;
}
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
    traitCollection:(UITraitCollection *)traits {
    return UIModalPresentationNone;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    _close = [[RBChromeButton alloc] initWithFrame:CGRectZero];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    [_close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:config] forState:UIControlStateNormal];
    _close.accessibilityLabel = _close.largeContentTitle = @"关闭画笔设置";
    [_close addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_close];
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.delaysContentTouches = NO;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:_scroll];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < RBBrushColorCount; i++) {
        UIButton *button = [[RBChromeButton alloc] initWithFrame:CGRectZero];
        button.accessibilityLabel = button.largeContentTitle = [NSString stringWithFormat:@"颜色 %lu", (unsigned long)i + 1];
        button.accessibilityHint = @"轻点使用，选中后再次轻点调色";
        button.tag = i;
        [button addTarget:self action:@selector(pick:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:button];
        [_scroll addSubview:button];
    }
    _buttons = buttons;
    [self addChildViewController:_widthController];
    [_scroll addSubview:_widthController.view];
    [_widthController didMoveToParentViewController:self];
    [self updateColors];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    _close.frame = CGRectMake((width - RBBrushClose) / 2, 0, RBBrushClose, RBBrushClose);
    _scroll.frame = CGRectMake(0, RBBrushClose, width, MAX(0, self.view.bounds.size.height - RBBrushClose));
    CGFloat y = 8;
    for (UIButton *button in _buttons) {
        button.frame = CGRectMake((width - RBBrushColorTarget) / 2, y, RBBrushColorTarget, RBBrushColorTarget);
        y += RBBrushColorTarget + RBBrushColorGap;
    }
    y += 8 - RBBrushColorGap;
    CGFloat height = _widthController.preferredContentSize.height;
    _widthController.view.frame = CGRectMake(0, y, width, height);
    _scroll.contentSize = CGSizeMake(width, y + height + 8);
}
- (void)preferredContentSizeDidChangeForChildContentContainer:(id<UIContentContainer>)container {
    [super preferredContentSizeDidChangeForChildContentContainer:container];
    [self.view setNeedsLayout];
}
- (BOOL)matchesColor:(UIColor *)color {
    CGFloat a[4], b[4];
    UIColor *current = [_color resolvedColorWithTraitCollection:self.traitCollection];
    color = [color resolvedColorWithTraitCollection:self.traitCollection];
    if (![current getRed:&a[0] green:&a[1] blue:&a[2] alpha:&a[3]] ||
        ![color getRed:&b[0] green:&b[1] blue:&b[2] alpha:&b[3]]) return [current isEqual:color];
    for (NSUInteger i = 0; i < 4; i++) if (fabs(a[i] - b[i]) > 0.015) return NO;
    return YES;
}
- (void)updateColors {
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        BOOL selected = _selectedSlot == (NSInteger)i;
        _buttons[i].accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(36, 36)];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGContextSetFillColorWithColor(context.CGContext,
                [self->_colors[i] resolvedColorWithTraitCollection:self.traitCollection].CGColor);
            CGContextFillEllipseInRect(context.CGContext, CGRectMake(5, 5, 26, 26));
            CGContextSetStrokeColorWithColor(context.CGContext,
                [UIColor.labelColor resolvedColorWithTraitCollection:self.traitCollection].CGColor);
            CGContextSetLineWidth(context.CGContext, 0.75);
            CGContextStrokeEllipseInRect(context.CGContext, CGRectMake(5, 5, 26, 26));
            if (selected) {
                CGContextSetLineWidth(context.CGContext, 1.5);
                CGContextStrokeEllipseInRect(context.CGContext, CGRectMake(1, 1, 34, 34));
            }
        }];
        [_buttons[i] setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    }
}
- (void)commitColor {
    if (!_colorDirty || _selectedSlot < 0) return;
    CGFloat r, g, b, a;
    UIColor *resolved = [_color resolvedColorWithTraitCollection:self.traitCollection];
    if (![resolved getRed:&r green:&g blue:&b alpha:&a]) return;
    _colorDirty = NO;
    RBSaveBrushColor((NSUInteger)_selectedSlot, @[@(r), @(g), @(b), @(a)]);
}
- (void)pick:(UIButton *)sender {
    if (RBBrushTapEdits(_selectedSlot, sender.tag)) {
        [self editColor:sender];
        return;
    }
    _selectedSlot = sender.tag;
    _color = _colors[sender.tag];
    _colorDirty = YES;
    [self updateColors];
    if (_colorChange) _colorChange(_color);
    [self commitColor];
}
- (void)editColor:(UIButton *)sender {
    if (_picker) return;
    [_widthController commitPendingWidth];
    _picker = [UIColorPickerViewController new];
    _picker.selectedColor = _color;
    _picker.supportsAlpha = NO;
    _picker.delegate = self;
    _picker.modalPresentationStyle = UIModalPresentationPopover;
    _picker.popoverPresentationController.delegate = self;
    _picker.popoverPresentationController.sourceView = sender;
    _picker.popoverPresentationController.sourceRect = sender.bounds;
    _picker.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    _picker.popoverPresentationController.passthroughViews = @[];
    _picker.popoverPresentationController.popoverLayoutMargins = UIEdgeInsetsMake(8, 8, 8, 8);
    [self updateAvailableSize:_availableSize];
    [self presentViewController:_picker animated:YES completion:nil];
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)picker {
    _color = picker.selectedColor;
    _colors[_selectedSlot] = _color;
    _colorDirty = YES;
    [self updateColors];
    if (_colorChange) _colorChange(_color);
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        [self commitColor];
        if (self->_picker == picker) self->_picker = nil;
    }];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller {
    [self commitColor];
    [_widthController commitPendingWidth];
    if (controller.presentedViewController == _picker) _picker = nil;
}
- (void)close:(UIButton *)sender {
    [self commitColor];
    [_widthController commitPendingWidth];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)viewWillDisappear:(BOOL)animated {
    [self commitColor];
    [super viewWillDisappear:animated];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.isViewLoaded) [self updateColors];
}
@end
