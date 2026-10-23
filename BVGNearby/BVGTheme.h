#import <UIKit/UIKit.h>

// Zentrales Design: Farben, Schriften, Systemdarstellung.
// Orientiert an aktuellem iOS-Design (inset grouped, grosse Titel), umgesetzt mit iOS-9-Mitteln.
@interface BVGTheme : NSObject

+ (void)applyAppearance;

// Farben
+ (UIColor *)background;     // hellgrauer Hintergrund (#F2F2F7)
+ (UIColor *)card;           // Kartenflaeche (weiss)
+ (UIColor *)cardPressed;    // Karte beim Antippen
+ (UIColor *)separator;
+ (UIColor *)textPrimary;
+ (UIColor *)textSecondary;
+ (UIColor *)textTertiary;
+ (UIColor *)accent;         // BVG-Gelb
+ (UIColor *)accentSoft;     // helles Gelb fuer Hervorhebungen
+ (UIColor *)link;           // iOS-Blau
+ (UIColor *)green;
+ (UIColor *)red;
+ (UIColor *)orange;

// Schriften (San Francisco)
+ (UIFont *)font:(CGFloat)size weight:(CGFloat)weight;
+ (UIFont *)digits:(CGFloat)size weight:(CGFloat)weight;   // gleich breite Ziffern -> kein Springen beim Herunterzaehlen

+ (CGFloat)cardInset;        // Abstand Karte <-> Bildschirmrand
+ (CGFloat)cardRadius;

@end
