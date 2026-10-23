#import <UIKit/UIKit.h>

// NSNull -> nil, damit JSON-Werte sicher abgefragt werden koennen
static inline id NN(id v) { return (v == [NSNull null]) ? nil : v; }

extern NSString * const BVGFavoritesChangedNotification;
extern NSString * const BVGAlarmsChangedNotification;

@interface BVGAPI : NSObject

// Netzwerk
+ (void)getJSON:(NSString *)path completion:(void (^)(id json, NSError *error))completion;
+ (NSString *)encode:(id)value;   // NSString, NSNumber, nil/NSNull -> URL-kodiert
+ (NSString *)lastSource;   // "serverlele" oder "transport.rest" - wer zuletzt geantwortet hat

// Zeit
+ (NSDate *)dateFromISO:(id)value;
+ (NSString *)isoFromDate:(NSDate *)date;
+ (NSString *)hhmm:(NSDate *)date;
+ (NSDate *)whenOfDeparture:(NSDictionary *)d;

// Darstellung
+ (UIColor *)bvgYellow;
+ (UIColor *)bvgBlue;
+ (UIColor *)colorForLine:(NSDictionary *)line;
+ (UIImage *)badgeForLine:(NSDictionary *)line;
+ (UIImage *)badgeStripForLines:(NSArray *)lines;
+ (UIImage *)dotWithColor:(UIColor *)color filled:(BOOL)filled;
+ (UIImage *)tabIconNamed:(NSString *)name;   // nearby, search, map, route, alarm, more
+ (UIImage *)smallIconNamed:(NSString *)name size:(CGFloat)size;   // Tab-Icon verkleinert
+ (UIImage *)stopSignWithSize:(CGFloat)diameter;   // gelber Kreis mit gruenem H
+ (NSString *)spokenLineName:(NSDictionary *)line;
+ (NSString *)shortName:(NSString *)name;   // "U Amrumer Str. (Berlin)" -> "U Amrumer Str."
+ (NSString *)platform:(NSString *)platform;   // "2 (U7)" -> "2"
+ (UIBarButtonItem *)barButtonWithIcon:(NSString *)icon target:(id)target action:(SEL)action;   // speaker, locate

// Favoriten & zuletzt angesehen
+ (NSArray *)favorites;
+ (BOOL)isFavorite:(NSString *)stopId;
+ (void)setFavorite:(BOOL)fav stopId:(NSString *)stopId name:(NSString *)name;
+ (NSArray *)recentStops;
+ (void)addRecentStop:(NSString *)stopId name:(NSString *)name;
+ (NSString *)nameForStop:(NSString *)stopId;
+ (void)syncWidget;   // Favoriten fuer das Mitteilungszentrale-Widget bereitstellen (App Group)

// Spotlight (iOS 9 Suche / Siri-Vorschlaege)
+ (void)indexStopInSpotlight:(NSString *)stopId name:(NSString *)name;
+ (NSString *)stopIdFromSpotlightIdentifier:(NSString *)identifier;

// Sprachausgabe
+ (void)speak:(NSString *)text;
+ (void)stopSpeaking;
+ (BOOL)isSpeaking;
+ (NSString *)announcementForStop:(NSString *)stopName departures:(NSArray *)deps max:(NSInteger)max;

// Wecker
+ (NSArray *)userAlarms;   // nur vom Nutzer gesetzte Wecker (ohne Navigations-Hinweise)
+ (BOOL)hasAlarmForTrip:(NSString *)tripId;
+ (void)cancelAlarmForTrip:(NSString *)tripId;
+ (void)presentAlarmSheetForDeparture:(NSDictionary *)d stopName:(NSString *)stopName from:(UIViewController *)vc;
+ (NSArray *)editActionsForDeparture:(NSDictionary *)d stopName:(NSString *)stopName from:(UITableViewController *)vc;

@end
