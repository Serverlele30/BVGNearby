#import <Foundation/Foundation.h>

extern NSString * const BVGSettingsChangedNotification;

@interface BVGSettings : NSObject
+ (NSInteger)radius;              // Suchradius in m (Standard 1000)
+ (NSInteger)departuresPerStop;   // Abfahrten pro Haltestelle (Standard 5)
+ (NSInteger)transferMinutes;     // Mindest-Umstiegszeit (Standard 5, nie weniger)
+ (NSInteger)boardLeadMinutes;    // Einsteige-Erinnerung vorher (Standard 2)
+ (BOOL)speechEnabled;            // Sprachansagen (Standard an)
+ (BOOL)useOwnServer;             // api.serverlele.de zuerst, transport.rest als Rueckfall (Standard an)

// Gespeicherte Orte ("home" / "work"): {name, id} fuer Haltestellen oder {name, latitude, longitude} fuer Adressen
+ (NSDictionary *)placeForKey:(NSString *)key;
+ (void)setPlace:(NSDictionary *)place forKey:(NSString *)key;

// Richtungsfilter pro Haltestelle (nil = alle Richtungen)
+ (NSString *)directionFilterForStop:(NSString *)stopId;
+ (void)setDirectionFilter:(NSString *)direction forStop:(NSString *)stopId;

+ (void)setInteger:(NSInteger)value forKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
@end
