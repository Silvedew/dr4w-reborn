#import "RBWidthPopover.h"
#import "RBStrokeWidth.h"

@interface RBWidthSlider : UISlider
@end
@implementation RBWidthSlider
- (void)accessibilityIncrement {
    self.value = MIN(self.maximumValue, self.value + 1);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)accessibilityDecrement {
    self.value = MAX(self.minimumValue, self.value - 1);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end

@interface RBWidthPreview : UIView
@property (nonatomic) CGFloat width;
@property (nonatomic) BOOL track;
@end
@implementation RBWidthPreview
- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (self.track) {
        CGFloat gap = 3, count = 12, size = (self.bounds.size.width - (count - 1) * gap) / count;
        CGFloat progress = (self.width - 1) / 29;
        for (NSInteger i = 0; i < count; i++) {
            CGFloat height = 1 + i * 0.8;
            UIColor *color = [UIColor.labelColor colorWithAlphaComponent:i / (count - 1) <= progress ? 0.8 : 0.18];
            CGContextSetFillColorWithColor(context, color.CGColor);
            CGContextFillRect(context, CGRectMake(i * (size + gap), (self.bounds.size.height - height) / 2, size, height));
        }
    } else {
        CGContextSetStrokeColorWithColor(context, UIColor.labelColor.CGColor);
        CGContextSetLineWidth(context, self.width);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextMoveToPoint(context, 24, self.bounds.size.height / 2);
        CGContextAddLineToPoint(context, self.bounds.size.width - 24, self.bounds.size.height / 2);
        CGContextStrokePath(context);
    }
}
@end

@implementation RBWidthPopover {
    CGFloat _width;
    BOOL _dirty;
    void (^_change)(CGFloat);
    void (^_commit)(CGFloat);
    RBWidthSlider *_slider;
    RBWidthPreview *_track;
    RBWidthPreview *_preview;
    UILabel *_title;
    UILabel *_value;
}
- (instancetype)initWithWidth:(CGFloat)width change:(void (^)(CGFloat))change commit:(void (^)(CGFloat))commit {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _width = RBStrokeWidth(width, 2);
        _change = [change copy];
        _commit = [commit copy];
        self.preferredContentSize = CGSizeMake(280, 164);
        self.modalPresentationStyle = UIModalPresentationPopover;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _title = [[UILabel alloc] initWithFrame:CGRectZero];
    _title.text = @"画笔粗细";
    _title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _title.adjustsFontForContentSizeCategory = YES;
    _title.textColor = UIColor.labelColor;
    _value = [[UILabel alloc] initWithFrame:CGRectZero];
    _value.textColor = UIColor.secondaryLabelColor;
    _value.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium];
    _value.textAlignment = NSTextAlignmentRight;
    _value.isAccessibilityElement = NO;
    [self.view addSubview:_title];
    [self.view addSubview:_value];
    _track = [[RBWidthPreview alloc] initWithFrame:CGRectZero];
    _track.track = YES;
    _track.backgroundColor = UIColor.clearColor;
    _track.userInteractionEnabled = NO;
    [self.view addSubview:_track];
    _slider = [[RBWidthSlider alloc] initWithFrame:CGRectZero];
    _slider.minimumValue = 1;
    _slider.maximumValue = 30;
    _slider.minimumTrackTintColor = UIColor.clearColor;
    _slider.maximumTrackTintColor = UIColor.clearColor;
    _slider.accessibilityLabel = @"画笔粗细";
    [_slider addTarget:self action:@selector(widthChanged:) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(commitWidth:) forControlEvents:
        UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.view addSubview:_slider];
    _preview = [[RBWidthPreview alloc] initWithFrame:CGRectZero];
    _preview.backgroundColor = UIColor.clearColor;
    _preview.isAccessibilityElement = NO;
    [self.view addSubview:_preview];
    [self updateWidth];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    _title.frame = CGRectMake(20, 12, MAX(0, width - 116), 32);
    _value.frame = CGRectMake(width - 92, 12, 72, 32);
    _slider.frame = CGRectMake(16, 52, width - 32, 52);
    CGRect track = [_slider trackRectForBounds:_slider.bounds];
    _track.frame = CGRectMake(_slider.frame.origin.x + track.origin.x + 16,
        _slider.frame.origin.y, MAX(0, track.size.width - 32), _slider.bounds.size.height);
    _preview.frame = CGRectMake(20, 112, width - 40, 36);
}
- (UIImage *)thumb {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(44, 44)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSetShadowWithColor(context.CGContext, CGSizeMake(0, 2), 4,
            [UIColor.blackColor colorWithAlphaComponent:0.18].CGColor);
        CGContextSetFillColorWithColor(context.CGContext,
            [UIColor.secondarySystemGroupedBackgroundColor resolvedColorWithTraitCollection:self.traitCollection].CGColor);
        CGContextFillEllipseInRect(context.CGContext, CGRectMake(5, 5, 34, 34));
        CGContextSetShadowWithColor(context.CGContext, CGSizeZero, 0, NULL);
        NSString *number = [NSString stringWithFormat:@"%.0f", self->_width];
        UIFont *font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightSemibold];
        NSDictionary *attributes = @{NSFontAttributeName:font,
            NSForegroundColorAttributeName:[UIColor.labelColor resolvedColorWithTraitCollection:self.traitCollection]};
        CGSize size = [number sizeWithAttributes:attributes];
        [number drawAtPoint:CGPointMake((44 - size.width) / 2, (44 - size.height) / 2) withAttributes:attributes];
    }];
}
- (void)updateWidth {
    _slider.value = _width;
    _slider.accessibilityValue = [NSString stringWithFormat:@"%.0f 磅", _width];
    _value.text = _slider.accessibilityValue;
    [_slider setThumbImage:[self thumb] forState:UIControlStateNormal];
    _track.width = _preview.width = _width;
    [_track setNeedsDisplay];
    [_preview setNeedsDisplay];
}
- (void)widthChanged:(UISlider *)sender {
    CGFloat width = RBStrokeWidth(sender.value, _width);
    sender.value = width;
    if (width == _width) return;
    _width = width;
    _dirty = YES;
    [self updateWidth];
    if (_change) _change(width);
}
- (void)commitWidth:(id)sender {
    if (!_dirty) return;
    _dirty = NO;
    if (_commit) _commit(_width);
}
- (void)viewWillDisappear:(BOOL)animated {
    [self commitWidth:nil]; // Also persists VoiceOver changes, which do not produce touch-up events.
    [super viewWillDisappear:animated];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.isViewLoaded) [self updateWidth];
}
@end
