#import "CardTableViewController.h"

// Sammelansicht aller Stoerungen/Hinweise an den angezeigten Haltestellen
@interface DisruptionsViewController : CardTableViewController
// stops: [{name, items: [{summary, text, lines}]}]
- (instancetype)initWithStops:(NSArray *)stops;
+ (NSArray *)collectFromStops:(NSArray *)stops;   // aus Haltestellen mit "departures" zusammenstellen
+ (NSInteger)countInCollection:(NSArray *)collection;
@end
