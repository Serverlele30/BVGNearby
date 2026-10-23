#import <UIKit/UIKit.h>

// Zentrales Design im Stil der BVG-App: gelber Kopfbereich, kraeftige schwarze Schrift,
// weisse Karten auf hellgrauem Grund. Nur iOS-9-Mittel.
@interface BVGTheme : NSObject

+ (void)applyAppearance;
+ (void)applyTabBarIndicator:(UITabBar *)bar count:(NSUInteger)count;   // gelber Balken ueber dem aktiven Tab

// Farben
+ (UIColor *)background;       // hellgrauer Hintergrund
+ (UIColor *)card;             // Kartenflaeche (weiss)
+ (UIColor *)cardPressed;      // Karte beim Antippen
+ (UIColor *)separator;
+ (UIColor *)textPrimary;      // schwarz
+ (UIColor *)textSecondary;
+ (UIColor *)textTertiary;
+ (UIColor *)accent;           // BVG-Gelb
+ (UIColor *)accentSoft;       // helles Gelb fuer Hervorhebungen
+ (UIColor *)header;           // Kopfbereich (= Gelb)
+ (UIColor *)headerText;       // Schrift auf Gelb
+ (UIColor *)headerSecondary;  // Nebentext auf Gelb (dunkel, gut lesbar)
+ (UIColor *)warningText;      // dunkles Orange, lesbar auf Gelb und Weiss
+ (UIColor *)searchField;    // Suchfeld-Hintergrund
+ (UIColor *)link;
+ (UIColor *)green;
+ (UIColor *)red;
+ (UIColor *)orange;

// Schriften (San Francisco)
+ (UIFont *)font:(CGFloat)size weight:(CGFloat)weight;
+ (UIFont *)digits:(CGFloat)size weight:(CGFloat)weight;   // gleich breite Ziffern -> kein Springen

+ (CGFloat)cardInset;          // Abstand Karte <-> Bildschirmrand
+ (CGFloat)cardRadius;

+ (UIImage *)imageWithColor:(UIColor *)color;
+ (UIImage *)roundedImageWithColor:(UIColor *)color radius:(CGFloat)radius;   // dehnbar, z.B. Suchfeld

@end
