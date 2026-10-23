// Widget fuer die iOS-9-Mitteilungszentrale ("Heute"):
// zeigt die naechsten Abfahrten der Favoriten - ohne Favoriten die naechsten Haltestellen per Standort.
// Wird von deploy.sh direkt mit clang gebaut (kein eigenes Xcode-Target noetig).

#import <UIKit/UIKit.h>
#import <NotificationCenter/NotificationCenter.h>
#import <CoreLocation/CoreLocation.h>

static NSString * const kAppGroup   = @"group.com.serverlele.BVGNearby";
static NSString * const kOwnBase    = @"https://api.serverlele.de/live_navi/v6";
static NSString * const kPublicBase = @"https://v6.bvg.transport.rest";
static NSString * const kCacheKey   = @"widgetCache";
static const NSInteger kMaxStops = 2, kPerStop = 3;
static const CGFloat kRowH = 30, kHeadH = 26;

static inline id NN(id v) { return (v == [NSNull null]) ? nil : v; }

@interface TodayViewController : UIViewController <NCWidgetProviding, CLLocationManagerDelegate>
@property (nonatomic, strong) NSArray *stops;   // [{id, name, departures:[...]}]
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, copy) void (^pending)(NCUpdateResult);
@property (nonatomic, assign) CGFloat laidOutWidth;
@end

@implementation TodayViewController

#pragma mark - Hilfen

+ (UIColor *)colorFromHex:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *h = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (h.length != 6) return nil;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:h] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

+ (UIColor *)colorForProduct:(NSString *)p {
    if ([p isEqualToString:@"suburban"]) return [UIColor colorWithRed:0.00 green:0.55 blue:0.24 alpha:1];
    if ([p isEqualToString:@"subway"])   return [UIColor colorWithRed:0.07 green:0.36 blue:0.66 alpha:1];
    if ([p isEqualToString:@"tram"])     return [UIColor colorWithRed:0.80 green:0.04 blue:0.13 alpha:1];
    if ([p isEqualToString:@"bus"])      return [UIColor colorWithRed:0.58 green:0.15 blue:0.43 alpha:1];
    if ([p isEqualToString:@"ferry"])    return [UIColor colorWithRed:0.00 green:0.50 blue:0.73 alpha:1];
    return [UIColor colorWithRed:0.89 green:0.00 blue:0.10 alpha:1];
}

+ (UIImage *)badgeForLine:(NSDictionary *)line {
    NSString *name = NN(line[@"name"]) ?: @"?";
    NSString *product = NN(line[@"product"]) ?: @"";
    NSDictionary *c = NN(line[@"color"]);
    UIColor *bg = [c isKindOfClass:[NSDictionary class]] ? [self colorFromHex:NN(c[@"bg"])] : nil;
    UIColor *fg = [c isKindOfClass:[NSDictionary class]] ? [self colorFromHex:NN(c[@"fg"])] : nil;
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightBold],
                             NSForegroundColorAttributeName: fg ?: [UIColor whiteColor] };
    CGSize t = [name sizeWithAttributes:attrs];
    CGSize size = CGSizeMake(MAX(34, ceil(t.width) + 10), 19);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGFloat r = [product isEqualToString:@"suburban"] ? size.height / 2 : ([product isEqualToString:@"subway"] ? 3 : 4);
    [(bg ?: [self colorForProduct:product]) setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:r] fill];
    [name drawAtPoint:CGPointMake((size.width - t.width) / 2, (size.height - t.height) / 2) withAttributes:attrs];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (NSString *)shortName:(NSString *)name {
    if (![name isKindOfClass:[NSString class]]) return @"";
    return [name stringByReplacingOccurrencesOfString:@"\\s*\\((Berlin|Bln)\\)" withString:@""
                                              options:NSRegularExpressionSearch range:NSMakeRange(0, name.length)];
}

+ (NSDate *)dateFromISO:(id)value {
    if (![value isKindOfClass:[NSString class]]) return nil;
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    });
    return [f dateFromString:value];
}

+ (NSString *)encode:(NSString *)s {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

- (NSUserDefaults *)shared {
    return [[NSUserDefaults alloc] initWithSuiteName:kAppGroup];
}

#pragma mark - Netzwerk (eigener Server, sonst transport.rest)

- (void)getJSON:(NSString *)path completion:(void (^)(id json))completion {
    BOOL own = ![[self shared] objectForKey:@"ownServer"] || [[self shared] boolForKey:@"ownServer"];
    NSArray *bases = own ? @[kOwnBase, kPublicBase] : @[kPublicBase];
    [self getJSON:path bases:bases index:0 completion:completion];
}

- (void)getJSON:(NSString *)path bases:(NSArray *)bases index:(NSUInteger)i completion:(void (^)(id json))completion {
    if (i >= bases.count) { completion(nil); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[bases[i] stringByAppendingString:path]]];
    req.timeoutInterval = 10;
    [req setValue:@"BVGNearby-Widget/1.0 (iOS 9; private app)" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        id json = (data && code == 200) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (!json) { [self getJSON:path bases:bases index:i + 1 completion:completion]; return; }
        completion(json);
    }] resume];
}

#pragma mark - Lebenszyklus

- (void)viewDidLoad {
    [super viewDidLoad];
    self.messageLabel = [[UILabel alloc] init];
    self.messageLabel.font = [UIFont systemFontOfSize:13];
    self.messageLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    self.messageLabel.numberOfLines = 0;
    [self.view addSubview:self.messageLabel];

    // letzte Daten sofort zeigen
    NSData *cache = [[NSUserDefaults standardUserDefaults] objectForKey:kCacheKey];
    NSArray *stops = [cache isKindOfClass:[NSData class]] ? [NSJSONSerialization JSONObjectWithData:cache options:0 error:nil] : nil;
    if ([stops isKindOfClass:[NSArray class]] && stops.count) [self showStops:stops];
    else [self showMessage:@"Lade Abfahrten …"];

    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
}

// Breite steht erst nach dem Layout fest -> dann einmal neu aufbauen
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    if (w > 0 && fabs(w - self.laidOutWidth) > 0.5) {
        self.laidOutWidth = w;
        if (self.stops.count) [self showStops:self.stops];
    }
}

// iOS 9 rueckt Widgets links weit ein - etwas weniger, damit mehr Platz fuer die Richtung bleibt
- (UIEdgeInsets)widgetMarginInsetsForProposedMarginInsets:(UIEdgeInsets)defaultMarginInsets {
    return UIEdgeInsetsMake(0, 16, 0, 0);
}

- (void)widgetPerformUpdateWithCompletionHandler:(void (^)(NCUpdateResult))completionHandler {
    NSArray *favs = [[self shared] arrayForKey:@"favorites"];
    if (favs.count) {
        NSMutableArray *list = [NSMutableArray array];
        for (NSDictionary *f in favs) {
            if (list.count >= kMaxStops) break;
            if (f[@"id"]) [list addObject:@{ @"id": f[@"id"], @"name": f[@"name"] ?: @"?" }];
        }
        [self loadDeparturesFor:list completion:completionHandler];
        return;
    }
    // keine Favoriten (oder App Group nicht verfuegbar): naechste Haltestellen per Standort
    self.pending = completionHandler;
    if (!self.locationManager) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    }
    CLAuthorizationStatus st = [CLLocationManager authorizationStatus];
    if (st == kCLAuthorizationStatusDenied || st == kCLAuthorizationStatusRestricted) {
        [self showMessage:@"Merke dir in der App Haltestellen mit ☆ – sie erscheinen dann hier."];
        [self finish:NCUpdateResultNoData];
        return;
    }
    if (st == kCLAuthorizationStatusNotDetermined) [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager requestLocation];
}

- (void)finish:(NCUpdateResult)result {
    void (^h)(NCUpdateResult) = self.pending;
    self.pending = nil;
    if (h) h(result);
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (!self.pending) return;   // nur einmal pro Aktualisierung
    CLLocationCoordinate2D c = locations.lastObject.coordinate;
    NSString *path = [NSString stringWithFormat:@"/locations/nearby?latitude=%.6f&longitude=%.6f&results=%ld&distance=1000&poi=false&addresses=false",
                      c.latitude, c.longitude, (long)kMaxStops];
    [self getJSON:path completion:^(id json) {
        NSMutableArray *list = [NSMutableArray array];
        if ([json isKindOfClass:[NSArray class]]) {
            for (NSDictionary *s in json) {
                if ([s isKindOfClass:[NSDictionary class]] && NN(s[@"id"])) [list addObject:@{ @"id": s[@"id"], @"name": NN(s[@"name"]) ?: @"?" }];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^h)(NCUpdateResult) = self.pending;
            self.pending = nil;
            if (!list.count) {
                [self showMessage:@"Keine Haltestellen in der Nähe gefunden."];
                if (h) h(NCUpdateResultFailed);
                return;
            }
            [self loadDeparturesFor:list completion:h];
        });
    }];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (!self.pending) return;
    [self showMessage:@"Standort nicht verfügbar. Merke dir in der App Haltestellen mit ☆."];
    [self finish:NCUpdateResultFailed];
}

#pragma mark - Abfahrten

- (void)loadDeparturesFor:(NSArray *)stops completion:(void (^)(NCUpdateResult))completion {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *s in stops) [result addObject:[s mutableCopy]];
    dispatch_group_t group = dispatch_group_create();
    __block BOOL anyOK = NO;
    for (NSMutableDictionary *s in result) {
        dispatch_group_enter(group);
        NSString *path = [NSString stringWithFormat:@"/stops/%@/departures?duration=60&results=%ld", s[@"id"], (long)(kPerStop + 3)];
        [self getJSON:path completion:^(id json) {
            NSArray *deps = ([json isKindOfClass:[NSDictionary class]] && [json[@"departures"] isKindOfClass:[NSArray class]])
                            ? json[@"departures"] : nil;
            @synchronized (s) {
                if (deps) { s[@"departures"] = deps; anyOK = YES; }
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (anyOK) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
            if (data) [[NSUserDefaults standardUserDefaults] setObject:data forKey:kCacheKey];
            [self showStops:result];
        } else if (!self.stops.count) {
            [self showMessage:@"Keine Verbindung zum Server."];
        }
        if (completion) completion(anyOK ? NCUpdateResultNewData : NCUpdateResultFailed);
    });
}

#pragma mark - Darstellung

- (void)showMessage:(NSString *)text {
    for (UIView *v in self.view.subviews) if (v != self.messageLabel) [v removeFromSuperview];
    self.stops = @[];
    self.messageLabel.hidden = NO;
    self.messageLabel.text = text;
    CGFloat w = self.view.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width - 16;
    self.messageLabel.frame = CGRectMake(0, 8, w - 16, 36);
    self.preferredContentSize = CGSizeMake(0, 52);
}

- (void)showStops:(NSArray *)stops {
    for (UIView *v in self.view.subviews) if (v != self.messageLabel) [v removeFromSuperview];
    self.messageLabel.hidden = YES;
    self.stops = stops;

    CGFloat w = self.view.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width - 16;
    CGFloat y = 4;
    NSDate *now = [NSDate date];
    for (NSUInteger si = 0; si < stops.count; si++) {
        NSDictionary *s = stops[si];
        UILabel *head = [[UILabel alloc] initWithFrame:CGRectMake(0, y, w - 16, kHeadH)];
        head.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        head.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        head.text = [[TodayViewController shortName:s[@"name"]] uppercaseString];
        head.tag = 1000 + si;   // Antippen -> Haltestelle in der App
        [self.view addSubview:head];
        y += kHeadH;

        NSInteger shown = 0;
        for (NSDictionary *d in s[@"departures"] ?: @[]) {
            if (shown >= kPerStop) break;
            if (![d isKindOfClass:[NSDictionary class]] || [NN(d[@"cancelled"]) boolValue]) continue;
            NSDate *when = [TodayViewController dateFromISO:NN(d[@"when"])] ?: [TodayViewController dateFromISO:NN(d[@"plannedWhen"])];
            NSInteger mins = when ? (NSInteger)floor([when timeIntervalSinceDate:now] / 60.0) : -1;
            if (when && mins < 0) continue;
            NSInteger delay = [NN(d[@"delay"]) integerValue] / 60;

            UIImageView *badge = [[UIImageView alloc] initWithImage:[TodayViewController badgeForLine:NN(d[@"line"])]];
            badge.frame = CGRectMake(0, y + (kRowH - 19) / 2, badge.image.size.width, 19);
            [self.view addSubview:badge];

            UILabel *dir = [[UILabel alloc] initWithFrame:CGRectMake(48, y, w - 48 - 16 - 62, kRowH)];
            dir.font = [UIFont systemFontOfSize:14];
            dir.textColor = [UIColor whiteColor];
            dir.text = [TodayViewController shortName:NN(d[@"direction"]) ?: @""];
            [self.view addSubview:dir];

            UILabel *min = [[UILabel alloc] initWithFrame:CGRectMake(w - 16 - 60, y, 60, kRowH)];
            min.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
            min.textAlignment = NSTextAlignmentRight;
            min.textColor = delay > 0 ? [UIColor colorWithRed:1 green:0.45 blue:0.4 alpha:1] : [UIColor whiteColor];
            min.text = !when ? @"–" : (mins <= 0 ? @"jetzt" : [NSString stringWithFormat:@"%ld min", (long)mins]);
            [self.view addSubview:min];

            y += kRowH;
            shown++;
        }
        if (!shown) {
            UILabel *none = [[UILabel alloc] initWithFrame:CGRectMake(0, y, w - 16, kRowH)];
            none.font = [UIFont systemFontOfSize:13];
            none.textColor = [UIColor colorWithWhite:1 alpha:0.6];
            none.text = @"Keine Abfahrten in der nächsten Stunde";
            [self.view addSubview:none];
            y += kRowH;
        }
        y += 6;
    }
    self.preferredContentSize = CGSizeMake(0, y + 2);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    // welche Haltestelle wurde angetippt? (Bereich ab ihrer Ueberschrift)
    CGPoint p = [tap locationInView:self.view];
    NSDictionary *hit = nil;
    for (UIView *v in self.view.subviews) {
        if (v.tag >= 1000 && v.frame.origin.y <= p.y && (NSUInteger)(v.tag - 1000) < self.stops.count) hit = self.stops[v.tag - 1000];
    }
    NSString *urlString = hit
        ? [NSString stringWithFormat:@"bvgnearby://stop?id=%@&name=%@",
           [TodayViewController encode:[hit[@"id"] description]], [TodayViewController encode:hit[@"name"] ?: @""]]
        : @"bvgnearby://";
    [self.extensionContext openURL:[NSURL URLWithString:urlString] completionHandler:nil];
}

@end
