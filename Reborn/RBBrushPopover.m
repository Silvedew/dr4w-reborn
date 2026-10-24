#import "RBBrushPopover.h"
#import "RBChrome.h"
#import "RBWidthPopover.h"
#include <math.h>

@interface RBBrushPopover () <UIColorPickerViewControllerDelegate>
@end

@implementation RBBrushPopover {
    UIColor *_color;
    void (^_colorChange)(UIColor *);
    RBWidthPopover *_widthController;
    UIScrollView *_scroll;
    UILabel *_heading;
    UILabel *_colorHeading;
    UIButton *_done;
    UIButton *_more;
    NSArray<UIColor *> *_colors;
    NSArray<UIButton *> *_buttons;
    NSArray<UILabel *> *_checks;
}
- (instancetype)initWithColor:(UIColor *)color width:(CGFloat)width
    colorChange:(void (^)(UIColor *))colorChange widthChange:(void (^)(CGFloat))widthChange
    widthCommit:(void (^)(CGFloat))widthCommit {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _color = color;
        _colorChange = [colorChange copy];
        _colors = @[[UIColor colorWithWhite:0.05 alpha:1], UIColor.systemRedColor,
            UIColor.systemBlueColor, UIColor.systemGreenColor];
        _widthController = [[RBWidthPopover alloc] initWithWidth:width change:widthChange commit:widthCommit];
        self.preferredContentSize = CGSizeMake(220, 676);
        self.modalPresentationStyle = UIModalPresentationPopover;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _heading = [[UILabel alloc] initWithFrame:CGRectZero];
    _heading.text = @"画笔";
    _heading.textColor = UIColor.labelColor;
    _heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _heading.adjustsFontForContentSizeCategory = YES;
    [self.view addSubview:_heading];
    _done = [[RBChromeButton alloc] initWithFrame:CGRectZero];
    [_done setTitle:@"完成" forState:UIControlStateNormal];
    [_done setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    _done.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _done.titleLabel.adjustsFontSizeToFitWidth = YES;
    _done.titleLabel.minimumScaleFactor = 0.5;
    [_done addTarget:self action:@selector(done:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_done];
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.delaysContentTouches = NO;
    _scroll.alwaysBounceVertical = NO;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:_scroll];
    _colorHeading = [[UILabel alloc] initWithFrame:CGRectZero];
    _colorHeading.text = @"颜色";
    _colorHeading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _colorHeading.textColor = UIColor.secondaryLabelColor;
    _colorHeading.adjustsFontForContentSizeCategory = YES;
    [_scroll addSubview:_colorHeading];
    NSMutableArray *buttons = [NSMutableArray array], *checks = [NSMutableArray array];
    NSArray *names = @[@"黑色", @"红色", @"蓝色", @"绿色"];
    for (NSUInteger i = 0; i < _colors.count; i++) {
        UIButton *button = [[RBChromeButton alloc] initWithFrame:CGRectZero];
        [button setTitle:names[i] forState:UIControlStateNormal];
        [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
        button.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
        button.accessibilityLabel = button.largeContentTitle = names[i];
        button.tag = i;
        [button addTarget:self action:@selector(pick:) forControlEvents:UIControlEventTouchUpInside];
        UILabel *check = [[UILabel alloc] initWithFrame:CGRectZero];
        check.text = @"✓";
        check.textColor = UIColor.labelColor;
        check.isAccessibilityElement = NO;
        [button addSubview:check];
        [checks addObject:check];
        [buttons addObject:button];
        [_scroll addSubview:button];
    }
    _buttons = buttons; _checks = checks;
    _more = [[RBChromeButton alloc] initWithFrame:CGRectZero];
    [_more setTitle:@"更多颜色" forState:UIControlStateNormal];
    [_more setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    _more.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _more.titleLabel.adjustsFontForContentSizeCategory = YES;
    _more.titleLabel.adjustsFontSizeToFitWidth = YES;
    _more.titleLabel.minimumScaleFactor = 0.7;
    [_more addTarget:self action:@selector(more:) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_more];
    [self addChildViewController:_widthController];
    [_scroll addSubview:_widthController.view];
    [_widthController didMoveToParentViewController:self];
    [self updateColors];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat header = MAX(52, _heading.font.lineHeight + 20);
    CGFloat row = MAX(44, _buttons.firstObject.titleLabel.font.lineHeight + 16);
    _heading.frame = CGRectMake(16, 0, width - 88, header);
    _done.frame = CGRectMake(width - 68, 4, 60, header - 8);
    _scroll.frame = CGRectMake(0, header, width, MAX(0, self.view.bounds.size.height - header));
    CGFloat colorHeadingHeight = MAX(28, _colorHeading.font.lineHeight + 4);
    _colorHeading.frame = CGRectMake(20, 8, width - 40, colorHeadingHeight);
    CGFloat y = colorHeadingHeight + 12;
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        _buttons[i].frame = CGRectMake(12, y, width - 24, row);
        _checks[i].frame = CGRectMake(width - 60, 0, 24, row);
        y += row + 8;
    }
    _more.frame = CGRectMake(12, y, width - 24, row);
    y += row + 12;
    CGFloat height = _widthController.preferredContentSize.height;
    _widthController.view.frame = CGRectMake(20, y, width - 40, height);
    _scroll.contentSize = CGSizeMake(width, y + height + 12);
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
        BOOL selected = [self matchesColor:_colors[i]];
        _checks[i].hidden = !selected;
        _buttons[i].accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(28, 28)];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGContextSetFillColorWithColor(context.CGContext,
                [self->_colors[i] resolvedColorWithTraitCollection:self.traitCollection].CGColor);
            CGContextFillEllipseInRect(context.CGContext, CGRectMake(2, 2, 24, 24));
            CGContextSetStrokeColorWithColor(context.CGContext,
                [UIColor.labelColor resolvedColorWithTraitCollection:self.traitCollection].CGColor);
            CGContextStrokeEllipseInRect(context.CGContext, CGRectMake(2, 2, 24, 24));
        }];
        [_buttons[i] setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    }
}
- (void)pick:(UIButton *)sender {
    _color = _colors[sender.tag];
    [self updateColors];
    if (_colorChange) _colorChange(_color);
}
- (void)more:(UIButton *)sender {
    [_widthController commitPendingWidth];
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.selectedColor = _color;
    picker.supportsAlpha = NO;
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationPopover;
    picker.preferredContentSize = CGSizeMake(320, 420);
    picker.popoverPresentationController.sourceView = sender;
    picker.popoverPresentationController.sourceRect = sender.bounds;
    picker.popoverPresentationController.passthroughViews = @[];
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)picker {
    _color = picker.selectedColor;
    [self updateColors];
    if (_colorChange) _colorChange(_color);
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)done:(UIButton *)sender {
    [_widthController commitPendingWidth];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.isViewLoaded) [self updateColors];
}
@end
