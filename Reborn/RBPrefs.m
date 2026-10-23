#import "RBPrefs.h"

static NSString *const kDomain = @"com.dsh.dr4wreborn";

@implementation RBPrefs

+ (NSUserDefaults *)defaults {
    return [[NSUserDefaults alloc] initWithSuiteName:kDomain];
}

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
    NSInteger i = [[self defaults] integerForKey:@"toolIndex"];
    NSArray *types = [self toolTypes];
    if (i < 0 || i >= (NSInteger)types.count) i = 0;
    return (ACEDrawingToolType)[types[i] integerValue];
}

+ (void)setTool:(ACEDrawingToolType)tool {
    NSArray *types = [self toolTypes];
    for (NSInteger i = 0; i < (NSInteger)types.count; i++) {
        if ([types[i] integerValue] == (NSInteger)tool) {
            [[self defaults] setInteger:i forKey:@"toolIndex"];
            return;
        }
    }
}

+ (NSString *)toolName {
    NSInteger i = [[self defaults] integerForKey:@"toolIndex"];
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
    NSInteger i = [[self defaults] integerForKey:@"colorIndex"];
    if (i < 0 || i >= (NSInteger)[self colors].count) i = 0;
    return i;
}

+ (UIColor *)color {
    if ([self hasCustomColor]) return [self customColor];
    return [self colors][[self colorIndex]];
}

+ (void)setColorIndex:(NSInteger)index {
    [[self defaults] setBool:NO forKey:@"hasCustom"];
    [[self defaults] setInteger:index forKey:@"colorIndex"];
}

+ (BOOL)hasCustomColor {
    return [[self defaults] boolForKey:@"hasCustom"];
}

+ (UIColor *)customColor {
    NSUserDefaults *d = [self defaults];
    return [UIColor colorWithRed:[d doubleForKey:@"cR"]
                           green:[d doubleForKey:@"cG"]
                            blue:[d doubleForKey:@"cB"]
                           alpha:[d doubleForKey:@"cA"]];
}

+ (void)setCustomColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSUserDefaults *d = [self defaults];
    [d setDouble:r forKey:@"cR"];
    [d setDouble:g forKey:@"cG"];
    [d setDouble:b forKey:@"cB"];
    [d setDouble:a forKey:@"cA"];
    [d setBool:YES forKey:@"hasCustom"];
}

+ (NSArray<NSNumber *> *)widths {
    return @[@2.0, @4.0, @7.0, @12.0, @20.0];
}

+ (NSInteger)widthIndex {
    NSInteger i = [[self defaults] integerForKey:@"widthIndex"];
    if (i < 0 || i >= (NSInteger)[self widths].count) i = 2;
    return i;
}

+ (CGFloat)lineWidth {
    return [[self widths][[self widthIndex]] doubleValue];
}

+ (void)setWidthIndex:(NSInteger)index {
    [[self defaults] setInteger:index forKey:@"widthIndex"];
}

+ (CGPoint)floatCenter {
    NSUserDefaults *d = [self defaults];
    if (![d objectForKey:@"floatX"]) {
        CGSize s = [UIScreen mainScreen].bounds.size;
        return CGPointMake(s.width - 40.0, s.height * 0.35);
    }
    CGPoint p;
    p.x = [d doubleForKey:@"floatX"];
    p.y = [d doubleForKey:@"floatY"];
    return p;
}

+ (void)setFloatCenter:(CGPoint)center {
    NSUserDefaults *d = [self defaults];
    [d setDouble:center.x forKey:@"floatX"];
    [d setDouble:center.y forKey:@"floatY"];
}

@end
