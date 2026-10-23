#import <UIKit/UIKit.h>
#import "CardCell.h"
#import "BVGTheme.h"

// Basis fuer alle Listen: Karten-Layout, moderne Abschnittstitel, grosser Titel, leere Zustaende.
@interface CardTableViewController : UITableViewController

// grosser Titel oben in der Liste (wird beim Scrollen in die Leiste uebernommen)
@property (nonatomic, copy) NSString *largeTitle;
@property (nonatomic, copy) NSString *largeSubtitle;
@property (nonatomic, strong) UIColor *largeSubtitleColor;
@property (nonatomic, strong) UIView *headerAccessory;   // z.B. Suchfeld oder Filter unter dem Titel
- (void)updateLargeHeader;

// leerer Zustand mittig in der Liste; icon/title/text = nil blendet ihn aus
- (void)showEmptyIcon:(NSString *)icon title:(NSString *)title text:(NSString *)text;

// Abschnittstitel im gleichen Stil, fuer eigene Header
+ (UILabel *)sectionLabelWithText:(NSString *)text;

@end
