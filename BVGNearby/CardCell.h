#import <UIKit/UIKit.h>

// Zelle im "inset grouped"-Stil: eingerueckt, Karte mit runden Ecken oben/unten pro Abschnitt.
// Die Position (erste/letzte Zeile) setzt CardTableViewController automatisch.
@interface CardCell : UITableViewCell
@property (nonatomic, strong) UIColor *cardColor;   // Standard: weiss
@property (nonatomic, assign) BOOL firstInSection;
@property (nonatomic, assign) BOOL lastInSection;
- (void)applyCardStyle;
@end

// Mehrzeilige Zelle: Symbol links, Titel + Detail beliebig lang.
// Die Hoehe wird selbst berechnet (iOS 9 kann das mit Standardzellen nicht zuverlaessig).
@interface InfoCell : CardCell
@property (nonatomic, strong, readonly) UIImageView *iconView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *detailLabel;
- (CGFloat)fittingHeightForTableWidth:(CGFloat)tableWidth;
@end
