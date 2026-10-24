#import "RBChrome.h"
#import <QuartzCore/QuartzCore.h>

@implementation RBChromeSurface {
    UIVisualEffectView *_material;
    BOOL _usesMaterial;
}
- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame usesMaterial:YES];
}
- (instancetype)initWithFrame:(CGRect)frame usesMaterial:(BOOL)usesMaterial {
    if ((self = [super initWithFrame:frame])) {
        _usesMaterial = usesMaterial;
        self.layer.cornerRadius = 22;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 14;
        if (usesMaterial) {
            _material = [[UIVisualEffectView alloc] initWithEffect:nil];
            _material.userInteractionEnabled = NO;
            _material.layer.cornerCurve = kCACornerCurveContinuous;
            _material.clipsToBounds = YES;
            [self addSubview:_material];
        }
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appearanceChanged:)
            name:UIAccessibilityReduceTransparencyStatusDidChangeNotification object:nil];
        [self refreshAppearance];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)appearanceChanged:(NSNotification *)note { [self refreshAppearance]; }
- (void)refreshAppearance {
    BOOL solid = !_usesMaterial || UIAccessibilityIsReduceTransparencyEnabled() ||
        self.traitCollection.accessibilityContrast == UIAccessibilityContrastHigh;
    _material.effect = solid ? nil : [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    self.backgroundColor = solid ? UIColor.secondarySystemBackgroundColor : UIColor.clearColor;
    self.layer.borderWidth = solid ? 1 : 0.5;
    self.layer.borderColor = [UIColor.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    self.layer.shadowOpacity = !_usesMaterial ? 0 :
        (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.28 : 0.12);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self refreshAppearance];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _material.frame = self.bounds;
    _material.layer.cornerRadius = self.layer.cornerRadius;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.layer.cornerRadius].CGPath;
}
@end

@implementation RBChromeButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 14;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.tintColor = UIColor.labelColor;
        self.showsLargeContentViewer = YES;
        [self addInteraction:[UILargeContentViewerInteraction new]];
    }
    return self;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    void (^feedback)(void) = ^{
        self.backgroundColor = highlighted ? UIColor.tertiarySystemFillColor : UIColor.clearColor;
        self.transform = highlighted && !UIAccessibilityIsReduceMotionEnabled()
            ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity;
    };
    if (highlighted || UIAccessibilityIsReduceMotionEnabled()) {
        [self.layer removeAllAnimations];
        feedback();
    } else [UIView animateWithDuration:0.16 delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:feedback completion:nil];
}
@end
