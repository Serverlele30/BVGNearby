#import <UIKit/UIKit.h>

// Zelle im "inset grouped"-Stil: eingerueckt, Karte mit runden Ecken oben/unten pro Abschnitt.
// Die Position (erste/letzte Zeile) setzt CardTableViewController automatisch.
@interface CardCell : UITableViewCell
@property (nonatomic, strong) UIColor *cardColor;   // Standard: weiss
@property (nonatomic, assign) BOOL firstInSection;
@property (nonatomic, assign) BOOL lastInSection;
- (void)applyCardStyle;
@end
