#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

typedef NS_ENUM(NSInteger, GuidanceStatus) {
    GuidanceStatusOK,        // alle Anschluesse erreichbar
    GuidanceStatusAtRisk,    // Anschluss knapp (< 1 min Puffer)
    GuidanceStatusBroken,    // Anschluss nicht erreichbar oder Ausfall
    GuidanceStatusDone       // Ziel erreicht
};

extern NSString * const GuidanceChangedNotification;
extern NSString * const GuidanceAlternativeCategory;   // Mitteilungs-Kategorie mit Knoepfen

// Begleitet eine Verbindung: Ein-/Aussteige-Erinnerungen, regelmaessige Echtzeit-Pruefung,
// Alternativsuche bei Problemen. Die Entscheidung trifft immer der Nutzer.
@interface GuidanceManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL active;
@property (nonatomic, readonly, strong) NSDictionary *journey;
@property (nonatomic, readonly) GuidanceStatus status;
@property (nonatomic, readonly, copy) NSString *problemText;
@property (nonatomic, readonly, strong) NSDictionary *alternative;
@property (nonatomic, readonly, strong) NSDate *lastCheck;
@property (nonatomic, readonly) BOOL checking;

- (void)startWithJourney:(NSDictionary *)journey;
- (void)stop;
- (void)checkNow;
- (void)acceptAlternative;
- (void)dismissAlternative;

- (NSString *)currentInstruction;
- (NSInteger)currentLegIndex;

+ (BOOL)isWalk:(NSDictionary *)leg;
+ (NSDate *)legDeparture:(NSDictionary *)leg;
+ (NSDate *)legArrival:(NSDictionary *)leg;
+ (NSTimeInterval)minTransferSlack:(NSArray *)legs;

@end
