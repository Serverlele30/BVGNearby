#import <UIKit/UIKit.h>

// Horizontale Filter-Chips (wie in aktuellen Apps) statt des alten iOS-7-Segmented-Controls.
@interface ChipBar : UIView
- (instancetype)initWithItems:(NSArray *)titles;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onChange)(NSInteger index);
@property (nonatomic, strong) UIColor *idleColor;   // Hintergrund nicht gewaehlter Chips
@end
