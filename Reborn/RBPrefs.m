#import "RBPrefs.h"

static NSString *const kDomain = @"com.dsh.dr4wreborn";

@implementation RBPrefs

+ (NSUserDefaults *)defaults {
    return [[NSUserDefaults alloc] initWithSuiteName:kDomain];
}

+ (NSArray<NSString *> *)toolNames {
    return @[@"Pen", @"Line", @"Arrow", @"Rectangle", @"Filled Rectangle",
             @"Ellipse", @"Filled Ellipse", @"Eraser", @"Text",
             @"Triangle", @"Pentagon", @"Hexagon"];
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

+ (NSInteger)colorIndex {
    NSInteger i = [[self defaults] integerForKey:@"colorIndex"];
    if (i < 0 || i >= (NSInteger)[self colors].count) i = 0;
    return i;
}

+ (UIColor *)color {
    return [self colors][[self colorIndex]];
}

+ (void)setColorIndex:(NSInteger)index {
    [[self defaults] setInteger:index forKey:@"colorIndex"];
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

@end
