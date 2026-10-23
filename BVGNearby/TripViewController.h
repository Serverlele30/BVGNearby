#import "CardTableViewController.h"

@interface TripViewController : CardTableViewController
- (instancetype)initWithTripId:(NSString *)tripId;
@property (nonatomic, strong) NSDictionary *line;     // line-Objekt aus der Abfahrt
@property (nonatomic, copy) NSString *stopName;       // eigene Haltestelle (wird hervorgehoben)
@end
