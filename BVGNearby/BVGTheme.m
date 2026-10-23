#import "BVGTheme.h"

@implementation BVGTheme

+ (UIColor *)rgb:(int)r :(int)g :(int)b {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
}

+ (UIColor *)background    { return [self rgb:242 :242 :247]; }
+ (UIColor *)card          { return [UIColor whiteColor]; }
+ (UIColor *)cardPressed   { return [self rgb:229 :229 :234]; }
+ (UIColor *)separator     { return [self rgb:224 :224 :228]; }
+ (UIColor *)textPrimary   { return [self rgb:17 :17 :20]; }
+ (UIColor *)textSecondary { return [self rgb:120 :120 :128]; }
+ (UIColor *)textTertiary  { return [self rgb:174 :174 :178]; }
+ (UIColor *)accent        { return [self rgb:247 :209 :23]; }
+ (UIColor *)accentSoft    { return [self rgb:255 :246 :204]; }
+ (UIColor *)link          { return [self rgb:0 :122 :255]; }
+ (UIColor *)green         { return [self rgb:52 :168 :83]; }
+ (UIColor *)red           { return [self rgb:255 :59 :48]; }
+ (UIColor *)orange        { return [self rgb:255 :149 :0]; }

+ (UIFont *)font:(CGFloat)size weight:(CGFloat)weight {
    return [UIFont systemFontOfSize:size weight:weight];
}

+ (UIFont *)digits:(CGFloat)size weight:(CGFloat)weight {
    return [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
}

+ (CGFloat)cardInset  { return 14; }
+ (CGFloat)cardRadius { return 12; }

+ (UIImage *)imageWithColor:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), YES, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, 1, 1));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (void)applyAppearance {
    // Navigationsleiste: flach, gleiche Farbe wie der Hintergrund, keine Trennlinie
    UINavigationBar *nav = [UINavigationBar appearance];
    [nav setBackgroundImage:[self imageWithColor:[self background]] forBarMetrics:UIBarMetricsDefault];
    nav.shadowImage = [[UIImage alloc] init];
    nav.translucent = NO;
    nav.barTintColor = [self background];
    nav.tintColor = [self textPrimary];
    nav.titleTextAttributes = @{ NSForegroundColorAttributeName: [self textPrimary],
                                 NSFontAttributeName: [self font:17 weight:UIFontWeightSemibold] };
    [[UIBarButtonItem appearance] setTitleTextAttributes:@{ NSFontAttributeName: [self font:17 weight:UIFontWeightRegular] }
                                                forState:UIControlStateNormal];

    // Tab-Leiste: weiss, Auswahl dunkel
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

@end
