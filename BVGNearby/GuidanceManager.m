#import "GuidanceManager.h"
#import "BVGAPI.h"
#import "BVGSettings.h"
#import <UIKit/UIKit.h>

NSString * const GuidanceChangedNotification = @"GuidanceChanged";

static NSString * const kSavedJourneyKey   = @"guidanceJourney";
static NSString * const kSavedAltKey       = @"guidanceAlternative";   // fuer "Uebernehmen" direkt aus der Mitteilung
NSString * const GuidanceAlternativeCategory = @"ALTERNATIVE";
static const NSTimeInterval kCheckInterval = 60;     // Echtzeit-Pruefung jede Minute
#define kBoardLead   ((NSTimeInterval)[BVGSettings boardLeadMinutes] * 60)   // Einsteigen-Hinweis (Einstellung)
static const CLLocationDistance kExitRadius = 400;   // Backup: Aussteigen per GPS-Naehe
#define kMinTransfer ((NSTimeInterval)[BVGSettings transferMinutes] * 60)    // Umstiegspuffer, nie unter 5 min

@interface GuidanceManager () <CLLocationManagerDelegate>
@property (nonatomic, readwrite) BOOL active;
@property (nonatomic, readwrite, strong) NSDictionary *journey;
@property (nonatomic, readwrite) GuidanceStatus status;
@property (nonatomic, readwrite, copy) NSString *problemText;
@property (nonatomic, readwrite, strong) NSDictionary *alternative;
@property (nonatomic, readwrite, strong) NSDate *lastCheck;
@property (nonatomic, readwrite) BOOL checking;

@property (nonatomic, copy) NSString *lastSearchedProblem;   // pro Problem nur einmal suchen/melden
@property (nonatomic, strong) NSMutableSet *exitAlertedLegs;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastLocation;
@property (nonatomic, assign) BOOL preciseLocation;
@end

@implementation GuidanceManager

+ (instancetype)shared {
    static GuidanceManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = [[GuidanceManager alloc] init];
        [m restore];
    });
    return m;
}

#pragma mark - Hilfen

+ (BOOL)isWalk:(NSDictionary *)leg {
    return [NN(leg[@"walking"]) boolValue] || !NN(leg[@"line"]);
}

+ (NSDate *)legDeparture:(NSDictionary *)leg {
    return [BVGAPI dateFromISO:leg[@"departure"]] ?: [BVGAPI dateFromISO:leg[@"plannedDeparture"]];
}

+ (NSDate *)legArrival:(NSDictionary *)leg {
    return [BVGAPI dateFromISO:leg[@"arrival"]] ?: [BVGAPI dateFromISO:leg[@"plannedArrival"]];
}

// kleinste Umstiegszeit (Ankunft -> naechste Abfahrt) einer Verbindung; ohne Umstieg: unendlich
+ (NSTimeInterval)minTransferSlack:(NSArray *)legs {
    NSTimeInterval min = DBL_MAX;
    NSDictionary *prev = nil;
    for (NSDictionary *leg in legs) {
        if ([self isWalk:leg]) continue;
        if (prev) {
            NSDate *a = [self legArrival:prev], *d = [self legDeparture:leg];
            if (a && d) min = MIN(min, [d timeIntervalSinceDate:a]);
        }
        prev = leg;
    }
    return min;
}

- (NSArray *)legs {
    id legs = NN(self.journey[@"legs"]);
    return [legs isKindOfClass:[NSArray class]] ? legs : @[];
}

- (void)changed {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:GuidanceChangedNotification object:nil];
    });
}

#pragma mark - Start / Stopp / Wiederherstellen

- (void)startWithJourney:(NSDictionary *)journey {
    self.journey = journey;
    self.active = YES;
    self.alternative = nil;
    self.problemText = nil;
    self.lastSearchedProblem = nil;
    self.exitAlertedLegs = [NSMutableSet set];
    self.lastCheck = [NSDate date];
    [self save];
    [self startMonitoring];
    [self evaluate];
}

- (void)stop {
    self.active = NO;
    self.journey = nil;
    self.alternative = nil;
    self.problemText = nil;
    [self.timer invalidate];
    self.timer = nil;
    [self.locationManager stopUpdatingLocation];
    [self cancelGuidanceNotifications];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSavedJourneyKey];
    [self changed];
}

// Alternative wird mitgespeichert: so funktioniert "Uebernehmen" auch, wenn iOS die App zwischendurch beendet hat
- (void)setAlternative:(NSDictionary *)alternative {
    _alternative = alternative;
    NSData *data = alternative ? [NSJSONSerialization dataWithJSONObject:alternative options:0 error:nil] : nil;
    if (data) [[NSUserDefaults standardUserDefaults] setObject:data forKey:kSavedAltKey];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSavedAltKey];
}

- (void)save {
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.journey options:0 error:nil];
    if (data) [[NSUserDefaults standardUserDefaults] setObject:data forKey:kSavedJourneyKey];
}

- (void)restore {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kSavedJourneyKey];
    if (![data isKindOfClass:[NSData class]]) return;
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *legs = NN(j[@"legs"]);
    NSDate *end = [legs isKindOfClass:[NSArray class]] ? [GuidanceManager legArrival:legs.lastObject] : nil;
    if (!end || [end timeIntervalSinceNow] < -600) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSavedJourneyKey];
        return;
    }
    self.journey = j;
    self.active = YES;
    self.exitAlertedLegs = [NSMutableSet set];
    NSData *altData = [[NSUserDefaults standardUserDefaults] objectForKey:kSavedAltKey];
    if ([altData isKindOfClass:[NSData class]]) {
        NSDictionary *alt = [NSJSONSerialization JSONObjectWithData:altData options:0 error:nil];
        if ([alt isKindOfClass:[NSDictionary class]]) _alternative = alt;
    }
    [self startMonitoring];
    [self checkNow];
}

- (void)startMonitoring {
    [self.timer invalidate];
    self.timer = [NSTimer timerWithTimeInterval:kCheckInterval target:self selector:@selector(checkNow) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];

    if (!self.locationManager) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
        self.locationManager.distanceFilter = 30;
        self.locationManager.pausesLocationUpdatesAutomatically = NO;

        // Hintergrund nur, wenn UIBackgroundModes=location in der Info.plist steht (sonst Absturz)
        NSArray *modes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIBackgroundModes"];
        if ([modes containsObject:@"location"] &&
            [self.locationManager respondsToSelector:@selector(setAllowsBackgroundLocationUpdates:)]) {
            self.locationManager.allowsBackgroundLocationUpdates = YES;
        }
    }
    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    self.preciseLocation = YES;   // erzwingt die erste Einstellung
    [self updateLocationAccuracy];
    [self.locationManager startUpdatingLocation];
}

// Akku sparen: genaues GPS nur, wenn es gebraucht wird (zu Fuss, kurz vor dem Einsteigen oder Aussteigen).
// Sonst grobe Ortung ueber Funkzellen - die App laeuft trotzdem im Hintergrund weiter und prueft jede Minute.
- (BOOL)needsPreciseLocation {
    NSArray *legs = [self legs];
    NSInteger idx = [self currentLegIndex];
    if (idx >= (NSInteger)legs.count) return NO;
    NSDictionary *leg = legs[idx];
    if ([GuidanceManager isWalk:leg]) return YES;
    NSDate *dep = [GuidanceManager legDeparture:leg];
    NSDate *arr = [GuidanceManager legArrival:leg];
    if (dep && [dep timeIntervalSinceNow] < 5 * 60 && [dep timeIntervalSinceNow] > -60) return YES;   // Einsteigen
    if (arr && [arr timeIntervalSinceNow] < 6 * 60) return YES;                                      // Aussteigen
    return NO;
}

- (void)updateLocationAccuracy {
    if (!self.locationManager) return;
    BOOL precise = [self needsPreciseLocation];
    if (precise == self.preciseLocation && self.locationManager.distanceFilter > 0) return;
    self.preciseLocation = precise;
    self.locationManager.desiredAccuracy = precise ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyThreeKilometers;
    self.locationManager.distanceFilter  = precise ? 30 : 1000;
}

#pragma mark - Pruefen

- (void)checkNow {
    if (!self.active || self.checking) return;
    [self updateLocationAccuracy];
    self.checking = YES;
    [self changed];

    NSString *token = NN(self.journey[@"refreshToken"]);
    if (!token) {
        [self finishCheck];
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/journeys/%@?stopovers=true&remarks=true", [BVGAPI encode:token]];
    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        NSDictionary *fresh = [json isKindOfClass:[NSDictionary class]] ? NN(json[@"journey"]) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([fresh isKindOfClass:[NSDictionary class]] && [NN(fresh[@"legs"]) isKindOfClass:[NSArray class]]) {
                self.journey = fresh;
                [self save];
            } else {
                NSLog(@"Refresh-Fehler: %@", error);
            }
            [self finishCheck];
        });
    }];
}

- (void)finishCheck {
    self.checking = NO;
    self.lastCheck = [NSDate date];
    [self evaluate];
}

- (void)evaluate {
    if (!self.active) return;
    NSArray *legs = [self legs];
    NSDate *now = [NSDate date];

    // Ziel erreicht?
    NSDate *end = [GuidanceManager legArrival:legs.lastObject];
    if (end && [end timeIntervalSinceDate:now] < 0) {
        self.status = GuidanceStatusDone;
        self.problemText = nil;
        self.alternative = nil;
        [self cancelGuidanceNotifications];
        if ([end timeIntervalSinceDate:now] < -600) { [self stop]; return; }
        [self changed];
        return;
    }

    GuidanceStatus status = GuidanceStatusOK;
    NSString *problem = nil;

    NSDictionary *prevTransit = nil;
    NSTimeInterval walk = 0;
    for (NSDictionary *leg in legs) {
        if ([GuidanceManager isWalk:leg]) {
            NSDate *d = [GuidanceManager legDeparture:leg], *a = [GuidanceManager legArrival:leg];
            if (d && a) walk += [a timeIntervalSinceDate:d];
            continue;
        }

        NSDate *dep = [GuidanceManager legDeparture:leg];
        NSDate *arr = [GuidanceManager legArrival:leg];
        NSString *lineName = NN(NN(leg[@"line"])[@"name"]) ?: @"?";

        // Ausfall eines noch nicht beendeten Abschnitts
        if ([NN(leg[@"cancelled"]) boolValue] && arr && [arr compare:now] == NSOrderedDescending) {
            status = GuidanceStatusBroken;
            problem = [NSString stringWithFormat:@"%@ fällt aus.", lineName];
            break;
        }

        // Umstieg erreichbar? Gesamtzeit zwischen Ankunft und Anschluss pruefen
        if (prevTransit && dep && [dep compare:now] == NSOrderedDescending) {
            NSDate *prevArr = [GuidanceManager legArrival:prevTransit];
            NSTimeInterval slack = [dep timeIntervalSinceDate:prevArr];          // verfuegbare Umstiegszeit
            NSTimeInterval physical = walk > 0 ? walk : 60;                      // reine Wegzeit, mind. 1 min
            NSTimeInterval wanted = MAX(kMinTransfer, physical);                 // gewuenschter Puffer
            NSString *prevName = NN(NN(prevTransit[@"line"])[@"name"]) ?: @"?";
            NSInteger prevDelay = [NN(prevTransit[@"arrivalDelay"]) integerValue] / 60;
            NSString *delayText = prevDelay > 0 ? [NSString stringWithFormat:@" (%@ +%ld min)", prevName, (long)prevDelay] : @"";

            if (slack < physical) {
                status = GuidanceStatusBroken;
                problem = [NSString stringWithFormat:@"Anschluss an %@ nicht erreichbar%@.", lineName, delayText];
                break;
            }
            if (slack < wanted && status == GuidanceStatusOK) {
                status = GuidanceStatusAtRisk;
                problem = [NSString stringWithFormat:@"Umstieg zu %@ nur noch %ld min statt mind. %ld min%@.",
                           lineName, (long)floor(slack / 60.0), (long)[BVGSettings transferMinutes], delayText];
            }
        }
        prevTransit = leg;
        walk = 0;
    }

    self.status = status;
    self.problemText = problem;

    if (status == GuidanceStatusOK) {
        self.alternative = nil;              // Problem hat sich erledigt
        self.lastSearchedProblem = nil;
    } else if (![problem isEqualToString:self.lastSearchedProblem]) {
        // auch bei zu knappem Puffer (< 5 min) schon eine Alternative vorschlagen
        self.lastSearchedProblem = problem;
        [self findAlternativeForProblem:problem];
    }

    [self scheduleGuidanceNotifications];
    [self changed];
}

#pragma mark - Alternativen

- (NSString *)endpointParam:(NSString *)prefix place:(NSDictionary *)place {
    NSString *sid = NN(place[@"id"]);
    NSString *type = NN(place[@"type"]);
    if (sid && ![type isEqualToString:@"location"]) return [NSString stringWithFormat:@"%@=%@", prefix, [BVGAPI encode:sid]];

    NSDictionary *loc = [NN(place[@"location"]) isKindOfClass:[NSDictionary class]] ? place[@"location"] : place;
    NSNumber *lat = NN(loc[@"latitude"]), *lon = NN(loc[@"longitude"]);
    if (!lat || !lon) return nil;
    return [NSString stringWithFormat:@"%@.latitude=%f&%@.longitude=%f&%@.address=%@", prefix, lat.doubleValue,
            prefix, lon.doubleValue, prefix, [BVGAPI encode:NN(place[@"name"]) ?: NN(place[@"address"]) ?: @"Ziel"]];
}

- (void)findAlternativeForProblem:(NSString *)problem {
    NSArray *legs = [self legs];
    NSDictionary *destination = NN(((NSDictionary *)legs.lastObject)[@"destination"]);
    NSString *toParam = [self endpointParam:@"to" place:destination];
    if (!toParam) return;

    // Start: aktueller Standort (frisch), sonst Start des naechsten offenen Abschnitts
    NSString *fromParam = nil;
    if (self.lastLocation && [self.lastLocation.timestamp timeIntervalSinceNow] > -300) {
        CLLocationCoordinate2D c = self.lastLocation.coordinate;
        fromParam = [NSString stringWithFormat:@"from.latitude=%f&from.longitude=%f&from.address=%@",
                     c.latitude, c.longitude, [BVGAPI encode:@"Mein Standort"]];
    } else {
        NSInteger idx = [self currentLegIndex];
        if (idx < (NSInteger)legs.count) fromParam = [self endpointParam:@"from" place:NN(legs[idx][@"origin"])];
    }
    if (!fromParam) return;

    NSDate *currentArrival = [GuidanceManager legArrival:legs.lastObject];
    NSString *path = [NSString stringWithFormat:@"/journeys?%@&%@&results=5&stopovers=true&remarks=true&transferTime=%ld",
                      fromParam, toParam, (long)[BVGSettings transferMinutes]];

    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        NSArray *list = [json isKindOfClass:[NSDictionary class]] ? NN(json[@"journeys"]) : nil;
        NSDictionary *best = nil;
        NSDate *bestArr = nil;
        for (NSDictionary *j in ([list isKindOfClass:[NSArray class]] ? list : @[])) {
            NSArray *jl = NN(j[@"legs"]);
            if (![jl isKindOfClass:[NSArray class]] || !jl.count) continue;
            BOOL cancelled = NO;
            for (NSDictionary *l in jl) if ([NN(l[@"cancelled"]) boolValue]) cancelled = YES;
            if (cancelled || [GuidanceManager minTransferSlack:jl] < kMinTransfer) continue;   // nur Alternativen mit >= 5 min Umstieg
            NSDate *arr = [GuidanceManager legArrival:jl.lastObject];
            if (arr && (!bestArr || [arr compare:bestArr] == NSOrderedAscending)) { best = j; bestArr = arr; }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.active) return;
            if (!best) {
                self.problemText = [problem stringByAppendingString:@" Keine Alternative gefunden."];
                [self notifyNow:[@"⚠ " stringByAppendingString:self.problemText] kind:@"alternative"];
                [self changed];
                return;
            }
            self.alternative = best;

            NSInteger diff = (currentArrival && bestArr) ? (NSInteger)round([bestArr timeIntervalSinceDate:currentArrival] / 60.0) : 0;
            NSMutableArray *lines = [NSMutableArray array];
            for (NSDictionary *l in best[@"legs"]) if (![GuidanceManager isWalk:l]) [lines addObject:NN(l[@"line"][@"name"]) ?: @"?"];
            NSString *text = [NSString stringWithFormat:@"⚠ %@ Alternative: %@, Ankunft %@%@. Wischen oder antippen zum Entscheiden.",
                              problem, [lines componentsJoinedByString:@" → "], [BVGAPI hhmm:bestArr],
                              diff > 0 ? [NSString stringWithFormat:@" (+%ld min)", (long)diff] : @""];
            [self notifyNow:text kind:@"alternative"];
            [self changed];
        });
    }];
}

- (void)acceptAlternative {
    if (!self.alternative) return;
    NSDictionary *alt = self.alternative;
    [self startWithJourney:alt];
}

- (void)dismissAlternative {
    self.alternative = nil;   // lastSearchedProblem bleibt -> gleiches Problem meldet sich nicht erneut
    [self changed];
}

#pragma mark - Anweisungen

- (NSInteger)currentLegIndex {
    NSArray *legs = [self legs];
    NSDate *now = [NSDate date];
    for (NSInteger i = 0; i < (NSInteger)legs.count; i++) {
        NSDate *arr = [GuidanceManager legArrival:legs[i]];
        if (!arr || [arr compare:now] != NSOrderedAscending) return i;
    }
    return legs.count;
}

- (NSString *)platformText:(NSString *)platform {
    platform = [BVGAPI platform:platform];
    return platform ? [NSString stringWithFormat:@", Gleis %@", platform] : @"";
}

- (NSString *)currentInstruction {
    NSArray *legs = [self legs];
    NSInteger idx = [self currentLegIndex];
    if (idx >= (NSInteger)legs.count) return @"Du hast dein Ziel erreicht.";

    NSDictionary *leg = legs[idx];
    NSDate *dep = [GuidanceManager legDeparture:leg];
    NSDate *arr = [GuidanceManager legArrival:leg];
    NSString *origin = NN(NN(leg[@"origin"])[@"name"]) ?: @"";
    NSString *dest   = NN(NN(leg[@"destination"])[@"name"]) ?: @"";

    if ([GuidanceManager isWalk:leg]) {
        NSInteger mins = (dep && arr) ? MAX(1, (NSInteger)round([arr timeIntervalSinceDate:dep] / 60.0)) : 1;
        return [NSString stringWithFormat:@"Geh zu Fuß zu %@, etwa %ld Minuten.", dest, (long)mins];
    }

    NSString *line = [BVGAPI spokenLineName:NN(leg[@"line"])];
    NSString *dir  = NN(leg[@"direction"]) ?: @"";
    if (dep && [dep timeIntervalSinceNow] > 0) {
        NSInteger mins = (NSInteger)floor([dep timeIntervalSinceNow] / 60.0);
        return [NSString stringWithFormat:@"Steig in %@ Richtung %@ ein, um %@ Uhr ab %@%@. %@",
                line, dir, [BVGAPI hhmm:dep], origin, [self platformText:NN(leg[@"departurePlatform"])],
                mins > 0 ? [NSString stringWithFormat:@"Noch %ld Minuten.", (long)mins] : @"Jetzt!"];
    }
    return [NSString stringWithFormat:@"Du fährst mit %@ bis %@. Ankunft %@ Uhr%@. Dort aussteigen.",
            line, dest, [BVGAPI hhmm:arr], [self platformText:NN(leg[@"arrivalPlatform"])]];
}

#pragma mark - Mitteilungen

- (void)cancelGuidanceNotifications {
    for (UILocalNotification *n in [[UIApplication sharedApplication] scheduledLocalNotifications]) {
        if ([n.userInfo[@"kind"] isEqualToString:@"guidance"]) [[UIApplication sharedApplication] cancelLocalNotification:n];
    }
}

- (void)notifyNow:(NSString *)text kind:(NSString *)kind {
    UILocalNotification *n = [[UILocalNotification alloc] init];
    n.alertBody = text;
    n.soundName = UILocalNotificationDefaultSoundName;   // bei Stumm: nur Vibration (System)
    n.userInfo = @{ @"kind": kind };
    if ([kind isEqualToString:@"alternative"]) n.category = GuidanceAlternativeCategory;   // Knoepfe Uebernehmen/Behalten
    [[UIApplication sharedApplication] presentLocalNotificationNow:n];
}

- (void)schedule:(NSString *)text at:(NSDate *)date legIndex:(NSInteger)idx {
    if (!date || [date timeIntervalSinceNow] < 5) return;
    UILocalNotification *n = [[UILocalNotification alloc] init];
    n.fireDate = date;
    n.alertBody = text;
    n.soundName = UILocalNotificationDefaultSoundName;
    n.userInfo = @{ @"kind": @"guidance", @"leg": @(idx) };
    [[UIApplication sharedApplication] scheduleLocalNotification:n];
}

- (void)scheduleGuidanceNotifications {
    [self cancelGuidanceNotifications];
    NSArray *legs = [self legs];

    for (NSInteger i = 0; i < (NSInteger)legs.count; i++) {
        NSDictionary *leg = legs[i];
        if ([GuidanceManager isWalk:leg] || [NN(leg[@"cancelled"]) boolValue]) continue;

        NSString *lineName = NN(NN(leg[@"line"])[@"name"]) ?: @"?";
        NSString *dir      = NN(leg[@"direction"]) ?: @"";
        NSString *origin   = NN(NN(leg[@"origin"])[@"name"]) ?: @"";
        NSString *dest     = NN(NN(leg[@"destination"])[@"name"]) ?: @"";
        NSDate *dep = [GuidanceManager legDeparture:leg];
        NSDate *arr = [GuidanceManager legArrival:leg];

        // 1) Einsteigen
        [self schedule:[NSString stringWithFormat:@"🚏 Gleich einsteigen: %@ → %@ um %@ ab %@%@",
                        lineName, dir, [BVGAPI hhmm:dep], origin, [self platformText:NN(leg[@"departurePlatform"])]]
                    at:[dep dateByAddingTimeInterval:-kBoardLead] legIndex:i];

        // 2) Aussteigen: wenn das Fahrzeug den vorletzten Halt verlaesst ("Naechster Halt: ...")
        if ([self.exitAlertedLegs containsObject:@(i)]) continue;
        NSDate *exitAt = nil;
        NSArray *stopovers = NN(leg[@"stopovers"]);
        if ([stopovers isKindOfClass:[NSArray class]] && stopovers.count >= 3) {
            NSDictionary *pen = stopovers[stopovers.count - 2];
            exitAt = [BVGAPI dateFromISO:pen[@"departure"]] ?: [BVGAPI dateFromISO:pen[@"plannedDeparture"]];
        }
        if (!exitAt) exitAt = [arr dateByAddingTimeInterval:-90];

        NSString *next = @"Das ist dein Ziel.";
        for (NSInteger k = i + 1; k < (NSInteger)legs.count; k++) {
            NSDictionary *nl = legs[k];
            if ([GuidanceManager isWalk:nl]) continue;
            next = [NSString stringWithFormat:@"Weiter mit %@ → %@ um %@%@.",
                    NN(NN(nl[@"line"])[@"name"]) ?: @"?", NN(nl[@"direction"]) ?: @"",
                    [BVGAPI hhmm:[GuidanceManager legDeparture:nl]], [self platformText:NN(nl[@"departurePlatform"])]];
            break;
        }
        [self schedule:[NSString stringWithFormat:@"🔔 Nächster Halt: %@ – bitte aussteigen! %@", dest, next]
                    at:exitAt legIndex:i];
    }
}

#pragma mark - Standort

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    self.lastLocation = locations.lastObject;
    if (!self.active) return;
    [self updateLocationAccuracy];

    // Hintergrund: falls der Timer nicht feuert, haelt der Standort die Pruefung am Laufen
    if (!self.lastCheck || [self.lastCheck timeIntervalSinceNow] < -kCheckInterval) [self checkNow];

    // Backup fuers Aussteigen: GPS-Naehe zum Ziel des laufenden Abschnitts
    NSArray *legs = [self legs];
    NSInteger idx = [self currentLegIndex];
    if (idx >= (NSInteger)legs.count) return;
    NSDictionary *leg = legs[idx];
    if ([GuidanceManager isWalk:leg] || [self.exitAlertedLegs containsObject:@(idx)]) return;

    NSDate *dep = [GuidanceManager legDeparture:leg];
    if (!dep || [dep timeIntervalSinceNow] > 0) return;   // noch nicht eingestiegen

    NSDictionary *loc = NN(NN(NN(leg[@"destination"])[@"location"]) ?: nil);
    if (![loc isKindOfClass:[NSDictionary class]]) return;
    CLLocation *target = [[CLLocation alloc] initWithLatitude:[loc[@"latitude"] doubleValue]
                                                    longitude:[loc[@"longitude"] doubleValue]];
    if ([self.lastLocation distanceFromLocation:target] > kExitRadius) return;

    [self.exitAlertedLegs addObject:@(idx)];
    [self notifyNow:[NSString stringWithFormat:@"🔔 Gleich da: %@ – bitte aussteigen!",
                     NN(NN(leg[@"destination"])[@"name"]) ?: @"Ziel"] kind:@"guidance"];
    [self scheduleGuidanceNotifications];   // geplante Aussteige-Meldung fuer diesen Abschnitt entfernen
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"Guidance-Location: %@", error);
}

@end
