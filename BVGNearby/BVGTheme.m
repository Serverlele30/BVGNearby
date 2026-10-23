#import "BVGTheme.h"

@implementation BVGTheme

+ (UIColor *)rgb:(int)r :(int)g :(int)b {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
}

+ (UIColor *)background      { return [self rgb:242 :242 :245]; }
+ (UIColor *)card            { return [UIColor whiteColor]; }
+ (UIColor *)cardPressed     { return [self rgb:228 :228 :228]; }
+ (UIColor *)separator       { return [self rgb:226 :226 :226]; }
+ (UIColor *)textPrimary     { return [self rgb:28 :28 :30]; }
+ (UIColor *)textSecondary   { return [self rgb:118 :118 :124]; }
+ (UIColor *)textTertiary    { return [self rgb:165 :165 :165]; }
+ (UIColor *)accent          { return [self rgb:240 :215 :34]; }
+ (UIColor *)accentSoft      { return [self rgb:255 :245 :190]; }
+ (UIColor *)header          { return [self accent]; }
+ (UIColor *)headerText      { return [self rgb:0 :0 :0]; }
+ (UIColor *)headerSecondary { return [self rgb:60 :54 :20]; }
+ (UIColor *)warningText     { return [self rgb:156 :72 :0]; }
+ (UIColor *)searchField     { return [UIColor whiteColor]; }
+ (UIColor *)link            { return [self rgb:0 :94 :184]; }
+ (UIColor *)green           { return [self rgb:0 :140 :60]; }
+ (UIColor *)red             { return [self rgb:210 :20 :30]; }
+ (UIColor *)orange          { return [self rgb:235 :120 :0]; }

+ (UIFont *)font:(CGFloat)size weight:(CGFloat)weight {
    return [UIFont systemFontOfSize:size weight:weight];
}

+ (UIFont *)digits:(CGFloat)size weight:(CGFloat)weight {
    return [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
}

+ (CGFloat)cardInset  { return 10; }
+ (CGFloat)cardRadius { return 10; }

+ (UIImage *)imageWithColor:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), YES, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, 1, 1));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)roundedImageWithColor:(UIColor *)color radius:(CGFloat)radius {
    CGFloat s = radius * 2 + 2;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:radius] fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

+ (void)applyAppearance {
    // Navigationsleiste: gelb, schwarze fette Schrift, ohne Trennlinie -> geht nahtlos in den Kopfbereich ueber
    UINavigationBar *nav = [UINavigationBar appearance];
    [nav setBackgroundImage:[self imageWithColor:[self header]] forBarMetrics:UIBarMetricsDefault];
    nav.shadowImage = [[UIImage alloc] init];
    nav.translucent = NO;
    nav.barTintColor = [self header];
    nav.tintColor = [self headerText];
    nav.titleTextAttributes = @{ NSForegroundColorAttributeName: [self headerText],
                                 NSFontAttributeName: [self font:17 weight:UIFontWeightSemibold] };
    [[UIBarButtonItem appearance] setTitleTextAttributes:@{ NSFontAttributeName: [self font:16 weight:UIFontWeightRegular] }
                                                forState:UIControlStateNormal];

    // Tab-Leiste: weiss, aktiver Tab schwarz mit gelbem Balken
    UITabBar *tab = [UITabBar appearance];
    tab.barTintColor = [UIColor whiteColor];
    tab.tintColor = [self textPrimary];
    tab.translucent = NO;
    [[UITabBarItem appearance] setTitleTextAttributes:@{ NSFontAttributeName: [self font:10 weight:UIFontWeightMedium],
                                                         NSForegroundColorAttributeName: [self textSecondary] }
                                             forState:UIControlStateNormal];
    [[UITabBarItem appearance] setTitleTextAttributes:@{ NSFontAttributeName: [self font:10 weight:UIFontWeightSemibold],
                                                         NSForegroundColorAttributeName: [self textPrimary] }
                                             forState:UIControlStateSelected];

    [UISwitch appearance].onTintColor = [self green];
    [UISegmentedControl appearance].tintColor = [self textPrimary];
}

+ (void)applyTabBarIndicator:(UITabBar *)bar count:(NSUInteger)count {
    if (!count) return;
    CGFloat w = floor([UIScreen mainScreen].bounds.size.width / count);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(w, 49), NO, 0);
    [[self accent] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(w * 0.2, 0, w * 0.6, 3)
                           byRoundingCorners:UIRectCornerBottomLeft | UIRectCornerBottomRight
                                 cornerRadii:CGSizeMake(2, 2)] fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    bar.selectionIndicatorImage = img;
}

@end
