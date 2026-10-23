#import "CardTableViewController.h"

@interface SearchViewController : CardTableViewController
// Gesetzt = Auswahlmodus (z.B. fuer den Routenplaner): Tippen liefert die Haltestelle zurueck
@property (nonatomic, copy) void (^pickHandler)(NSDictionary *stop);
// im Auswahlmodus auch Adressen anbieten (z.B. fuer "Zuhause")
@property (nonatomic, assign) BOOL allowAddresses;
@end
