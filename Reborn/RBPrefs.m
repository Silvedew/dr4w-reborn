#import "RBPrefs.h"
#import "RBSettings.h"
#import "RBStrokeWidth.h"
#import "RBToolbarLayout.h"

@implementation RBPrefs

+ (NSArray<NSString *> *)toolNames {
    return @[@"钢笔", @"直线", @"箭头", @"矩形", @"实心矩形",
             @"椭圆", @"实心椭圆", @"橡皮", @"文字",
             @"三角形", @"五边形", @"六边形"];
}

+ (NSArray<NSNumber *> *)toolTypes {
    return @[@(ACEDrawingToolTypePen), @(ACEDrawingToolTypeLine), @(ACEDrawingToolTypeArrow),
             @(ACEDrawingToolTypeRectagleStroke), @(ACEDrawingToolTypeRectagleFill),
             @(ACEDrawingToolTypeEllipseStroke), @(ACEDrawingToolTypeEllipseFill),
             @(ACEDrawingToolTypeEraser), @(ACEDrawingToolTypeDraggableText),
             @(ACEDrawingToolTypeTriangleStroke), @(ACEDrawingToolTypePentagonStroke),
             @(ACEDrawingToolTypeHexagoneStroke)];
}

+ (ACEDrawingToolType)tool {
    NSInteger i = [RBSetting(@"toolIndex", @0) integerValue];
    NSArray *types = [self toolTypes];
    if (i < 0 || i >= (NSInteger)types.count) i = 0;
    return (ACEDrawingToolType)[types[i] integerValue];
}

+ (void)setTool:(ACEDrawingToolType)tool {
    NSArray *types = [self toolTypes];
    for (NSInteger i = 0; i < (NSInteger)types.count; i++) {
        if ([types[i] integerValue] == (NSInteger)tool) {
            RBWriteSetting(@"toolIndex", @(i));
            return;
        }
    }
}

+ (NSString *)toolName {
    NSInteger i = [RBSetting(@"toolIndex", @0) integerValue];
    NSArray *names = [self toolNames];
    if (i < 0 || i >= (NSInteger)names.count) i = 0;
    return names[i];
}

+ (NSArray<UIColor *> *)colors {
    return @[[UIColor colorWithWhite:0.05 alpha:1.0],
             [UIColor whiteColor],
             [UIColor systemRedColor],
             [UIColor systemOrangeColor],
             [UIColor systemYellowColor],
             [UIColor systemGreenColor],
             [UIColor systemBlueColor],
             [UIColor systemPurpleColor]];
}

+ (NSArray<NSString *> *)colorNames {
    return @[@"黑色", @"白色", @"红色", @"橙色", @"黄色", @"绿色", @"蓝色", @"紫色"];
}

+ (NSInteger)colorIndex {
    NSInteger i = [RBSetting(@"colorIndex", @0) integerValue];
    if (i < 0 || i >= (NSInteger)[self colors].count) i = 0;
    return i;
}

+ (UIColor *)color {
    if ([self hasCustomColor]) return [self customColor];
    return [self colors][[self colorIndex]];
}

+ (void)setColorIndex:(NSInteger)index {
    RBWriteSetting(@"hasCustom", @NO);
    RBWriteSetting(@"colorIndex", @(index));
}

+ (BOOL)hasCustomColor {
    return [RBSetting(@"hasCustom", @NO) boolValue];
}

+ (UIColor *)customColor {
    return [UIColor colorWithRed:[RBSetting(@"cR", @0) doubleValue]
                           green:[RBSetting(@"cG", @0) doubleValue]
                            blue:[RBSetting(@"cB", @0) doubleValue]
                           alpha:[RBSetting(@"cA", @1) doubleValue]];
}

+ (void)setCustomColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    RBWriteSetting(@"cR", @(r));
    RBWriteSetting(@"cG", @(g));
    RBWriteSetting(@"cB", @(b));
    RBWriteSetting(@"cA", @(a));
    RBWriteSetting(@"hasCustom", @YES);
}

+ (NSArray<NSNumber *> *)widths {
    return @[@2.0, @4.0, @7.0, @12.0, @20.0];
}

+ (NSInteger)widthIndex {
    NSInteger i = [RBSetting(@"widthIndex", @0) integerValue];
    if (i < 0 || i >= (NSInteger)[self widths].count) i = 2;
    return i;
}

+ (CGFloat)lineWidth {
    double legacy = RBStrokeWidthFromLegacyIndex([self widthIndex]);
    id value = RBSetting(@"strokeWidth", nil);
    return [value isKindOfClass:NSNumber.class] ? RBStrokeWidth([value doubleValue], legacy) : legacy;
}

+ (void)setLineWidth:(CGFloat)width {
    RBWriteSetting(@"strokeWidth", @(RBStrokeWidth(width, [self lineWidth])));
}

+ (void)setWidthIndex:(NSInteger)index {
    RBWriteSetting(@"widthIndex", @(index));
    [self setLineWidth:RBStrokeWidthFromLegacyIndex(index)];
}

+ (CGPoint)floatCenter {
    if (!RBSetting(@"floatX", nil)) {
        CGSize s = [UIScreen mainScreen].bounds.size;
        return CGPointMake(s.width - 40.0, s.height * 0.35);
    }
    CGPoint p;
    p.x = [RBSetting(@"floatX", @0) doubleValue];
    p.y = [RBSetting(@"floatY", @0) doubleValue];
    return p;
}

+ (void)setFloatCenter:(CGPoint)center {
    RBWriteSetting(@"floatX", @(center.x));
    RBWriteSetting(@"floatY", @(center.y));
}

#pragma mark - ball

+ (CGFloat)ballSize {
    CGFloat v = [RBSetting(@"ballSize", @0) doubleValue];
    if (v < 44.0 || v > 80.0) v = 56.0;
    return v;
}

+ (void)setBallSize:(CGFloat)size {
    RBWriteSetting(@"ballSize", @(size));
}

+ (CGFloat)ballAlpha {
    CGFloat v = [RBSetting(@"ballAlpha", @0) doubleValue];
    if (v < 0.3 || v > 1.0) v = 1.0;
    return v;
}

+ (void)setBallAlpha:(CGFloat)alpha {
    RBWriteSetting(@"ballAlpha", @(alpha));
}

+ (CGFloat)toolbarScale {
    id value = RBSetting(@"toolbarScale", @1);
    double scale = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 1;
    return isfinite(scale) && scale >= 0.6 && scale <= 1.5 ? scale : 1;
}

+ (void)setToolbarScale:(CGFloat)scale {
    if (isfinite(scale) && scale >= 0.6 && scale <= 1.5) RBWriteSetting(@"toolbarScale", @(scale));
}

#pragma mark - per-app switch

+ (BOOL)isAppDisabled:(NSString *)bundleID {
    return !RBBallForBundle(bundleID);
}

@end
