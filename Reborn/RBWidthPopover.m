#import "RBWidthPopover.h"
#import "RBStrokeWidth.h"

@interface RBWidthSlider : UISlider
@end
@implementation RBWidthSlider {
    __weak UIScrollView *_scroll;
    BOOL _restoreScrolling;
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = [super beginTrackingWithTouch:touch withEvent:event];
    if (tracking) {
        for (UIView *view = self.superview; view; view = view.superview) {
            if (![view isKindOfClass:UIScrollView.class]) continue;
            _scroll = (UIScrollView *)view;
            _restoreScrolling = _scroll.scrollEnabled;
            _scroll.scrollEnabled = NO;
            break;
        }
    }
    return tracking;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super endTrackingWithTouch:touch withEvent:event];
    _scroll.scrollEnabled = _restoreScrolling;
    _scroll = nil;
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [super cancelTrackingWithEvent:event];
    _scroll.scrollEnabled = _restoreScrolling;
    _scroll = nil;
}
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
        CGFloat inset = MIN(24, self.bounds.size.width / 4);
        CGContextMoveToPoint(context, inset, self.bounds.size.height / 2);
        CGContextAddLineToPoint(context, self.bounds.size.width - inset, self.bounds.size.height / 2);
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
}
- (instancetype)initWithWidth:(CGFloat)width change:(void (^)(CGFloat))change commit:(void (^)(CGFloat))commit {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _width = RBStrokeWidth(width, 2);
        _change = [change copy];
        _commit = [commit copy];
        self.preferredContentSize = CGSizeMake(60, 184);
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
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
    CGSize preferred = CGSizeMake(60, 184);
    if (!CGSizeEqualToSize(preferred, self.preferredContentSize)) self.preferredContentSize = preferred;
    _slider.bounds = CGRectMake(0, 0, 124, 44);
    _slider.center = CGPointMake(width / 2, 72);
    _slider.transform = CGAffineTransformMakeRotation(-M_PI_2);
    _track.bounds = CGRectMake(0, 0, 92, 44);
    _track.center = _slider.center;
    _track.transform = _slider.transform;
    _preview.frame = CGRectMake(8, 140, width - 16, 32);
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
        // Counter-rotate the numeral; the slider itself rotates left to make up increase the value.
        CGContextTranslateCTM(context.CGContext, 22, 22);
        CGContextRotateCTM(context.CGContext, M_PI_2);
        [number drawAtPoint:CGPointMake(-size.width / 2, -size.height / 2) withAttributes:attributes];
    }];
}
- (void)updateWidth {
    _slider.value = _width;
    _slider.accessibilityValue = [NSString stringWithFormat:@"%.0f 磅", _width];
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
- (void)commitPendingWidth { [self commitWidth:nil]; }
- (void)viewWillDisappear:(BOOL)animated {
    [self commitWidth:nil]; // Also persists VoiceOver changes, which do not produce touch-up events.
    [super viewWillDisappear:animated];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.isViewLoaded) [self updateWidth];
}
@end
