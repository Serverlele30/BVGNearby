#import "CardCell.h"

@interface DepartureCell : CardCell
+ (CGFloat)height;
- (void)configureWithDeparture:(NSDictionary *)d;
- (void)configureEmpty:(NSString *)text;
- (void)setDimmed:(BOOL)dimmed;   // z.B. zu Fuss nicht mehr erreichbar
@end
