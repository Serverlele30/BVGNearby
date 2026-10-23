#import "ViewController.h"
#import "TripViewController.h"
#import "StopViewController.h"
#import "SearchViewController.h"
#import "DepartureCell.h"
#import "BVGAPI.h"
#import "BVGSettings.h"
#import "DisruptionsViewController.h"
#import <CoreLocation/CoreLocation.h>

static NSString * const kCacheKey = @"nearbyCache";

#pragma mark - Kopfzeile einer Haltestellen-Karte

@interface StopHeaderCell : CardCell
@property (nonatomic, strong) UIImageView *signView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *starButton;
@end

@implementation StopHeaderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _signView = [[UIImageView alloc] initWithImage:[BVGAPI stopSignWithSize:24]];
        [self.contentView addSubview:_signView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [BVGTheme textPrimary];
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.85;
        [self.contentView addSubview:_nameLabel];

        _metaLabel = [[UILabel alloc] init];
        _metaLabel.font = [BVGTheme font:12 weight:UIFontWeightRegular];
        _metaLabel.textColor = [BVGTheme textSecondary];
        [self.contentView addSubview:_metaLabel];

        _starButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _starButton.titleLabel.font = [UIFont systemFontOfSize:20];
        [self.contentView addSubview:_starButton];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    self.signView.frame   = CGRectMake(12, 12, 24, 24);
    self.nameLabel.frame  = CGRectMake(46, 7, w - 46 - 46, 20);
    self.metaLabel.frame  = CGRectMake(46, 27, w - 46 - 46, 15);
    self.starButton.frame = CGRectMake(w - 44, 2, 44, 44);
}

@end

#pragma mark - Abfahrten in der Naehe

@interface ViewController () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSArray *stops;   // [NSMutableDictionary: id, name, distance, fav, departures]
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSTimer *tick;     // Minuten lokal herunterzaehlen (auch offline)
@property (nonatomic, strong) NSDate *dataTime;  // Stand der angezeigten Daten
@property (nonatomic, assign) BOOL offline;
@property (nonatomic, assign) NSInteger bannerCount;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL waitingForLocation;
@end

@implementation ViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.largeTitle = @"Abfahrten";
    self.largeSubtitle = @"In deiner Nähe";
    self.stops = @[];
    self.bannerCount = 0;
    [self buildHeaderAccessory];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    [self.tableView addGestureRecognizer:press];

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(favoritesChanged) name:BVGFavoritesChangedNotification object:nil];
    [nc addObserver:self.tableView selector:@selector(reloadData) name:BVGAlarmsChangedNotification object:nil];
    [nc addObserver:self selector:@selector(settingsChanged) name:BVGSettingsChangedNotification object:nil];

    self.navigationItem.rightBarButtonItem = [BVGAPI barButtonWithIcon:@"speaker" target:self action:@selector(announceNearest)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Abfahrten ansagen";

    // Sofort die letzten bekannten Daten zeigen, waehrend neu geladen wird
    if (![self loadCache]) [self showEmptyIcon:@"📍" title:@"Einen Moment" text:@"Suche Haltestellen in deiner Nähe …"];

    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    } else {
        [self refresh];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self.tableView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.tableView reloadData];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    self.tick  = [NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(tickUpdate) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    [self.tick invalidate];
    self.timer = nil;
    self.tick = nil;
}

- (void)tickUpdate {
    if (self.tableView.editing || self.tableView.isDragging || self.loading) return;   // Wischaktionen nicht stoeren
    [self updateStatusHeader];
    [self.tableView reloadData];
}

- (void)settingsChanged {
    [self.tableView reloadData];
    [self refresh];
}

#pragma mark - Kopfbereich: Suchfeld + Stoerungs-Hinweis

- (void)buildHeaderAccessory {
    CGFloat w = self.view.bounds.size.width;
    CGFloat inset = [BVGTheme cardInset];
    CGFloat h = 36 + (self.bannerCount > 0 ? 42 : 0);
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];

    // weisses "Suchfeld" - oeffnet die Haltestellensuche
    UIButton *search = [UIButton buttonWithType:UIButtonTypeCustom];
    search.frame = CGRectMake(inset, 0, w - 2 * inset, 36);
    search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [search setBackgroundImage:[BVGTheme roundedImageWithColor:[BVGTheme searchField] radius:9] forState:UIControlStateNormal];
    [search setBackgroundImage:[BVGTheme roundedImageWithColor:[BVGTheme cardPressed] radius:9] forState:UIControlStateHighlighted];
    search.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    search.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    search.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    [search setImage:[BVGAPI smallIconNamed:@"search" size:15] forState:UIControlStateNormal];
    search.tintColor = [BVGTheme textSecondary];
    search.titleLabel.font = [BVGTheme font:15 weight:UIFontWeightRegular];
    [search setTitle:@"Haltestelle suchen" forState:UIControlStateNormal];
    [search setTitleColor:[BVGTheme textSecondary] forState:UIControlStateNormal];
    search.accessibilityLabel = @"Haltestelle suchen";
    [search addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:search];

    // schwarzer Hinweis-Balken bei Stoerungen an den angezeigten Haltestellen
    if (self.bannerCount > 0) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(inset, 42, w - 2 * inset, 34);
        b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [b setBackgroundImage:[BVGTheme roundedImageWithColor:[BVGTheme accentSoft] radius:9] forState:UIControlStateNormal];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        b.titleLabel.font = [BVGTheme font:13 weight:UIFontWeightSemibold];
        [b setTitleColor:[BVGTheme warningText] forState:UIControlStateNormal];
        [b setTitle:[NSString stringWithFormat:@"⚠︎  %ld %@ an deinen Haltestellen  ›", (long)self.bannerCount,
                     self.bannerCount == 1 ? @"Hinweis" : @"Hinweise"] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(openDisruptions) forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:b];
    }
    self.headerAccessory = v;
}

- (void)openSearch {
    SearchViewController *search = [[SearchViewController alloc] initWithStyle:UITableViewStylePlain];
    [self.navigationController pushViewController:search animated:YES];
}

#pragma mark - Cache & Offline-Hinweis

- (void)saveCache {
    NSDictionary *payload = @{ @"time": @([[NSDate date] timeIntervalSince1970]), @"stops": self.stops ?: @[] };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (data) [[NSUserDefaults standardUserDefaults] setObject:data forKey:kCacheKey];
}

- (BOOL)loadCache {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kCacheKey];
    if (![data isKindOfClass:[NSData class]]) return NO;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    NSArray *stops = payload[@"stops"];
    NSDate *time = [NSDate dateWithTimeIntervalSince1970:[payload[@"time"] doubleValue]];
    if (![stops isKindOfClass:[NSArray class]] || !stops.count || [time timeIntervalSinceNow] < -6 * 3600) return NO;
    self.stops = stops;
    self.dataTime = time;
    [self updateStatusHeader];
    [self updateDisruptionBanner];
    [self.tableView reloadData];
    return YES;
}

// Untertitel unter dem grossen Titel: Stand / offline
- (void)updateStatusHeader {
    NSTimeInterval age = self.dataTime ? -[self.dataTime timeIntervalSinceNow] : 0;
    if (self.offline && self.dataTime) {
        self.largeSubtitleColor = [BVGTheme red];
        self.largeSubtitle = [NSString stringWithFormat:@"Offline · Daten von %@ Uhr", [BVGAPI hhmm:self.dataTime]];
    } else if (self.dataTime && age > 120) {
        self.largeSubtitleColor = [BVGTheme warningText];
        self.largeSubtitle = [NSString stringWithFormat:@"Stand %@ Uhr · wird aktualisiert …", [BVGAPI hhmm:self.dataTime]];
    } else if (self.dataTime) {
        self.largeSubtitleColor = nil;
        self.largeSubtitle = [NSString stringWithFormat:@"In deiner Nähe · live, %@ Uhr", [BVGAPI hhmm:self.dataTime]];
    } else {
        self.largeSubtitleColor = nil;
        self.largeSubtitle = @"In deiner Nähe";
    }
}

- (void)updateDisruptionBanner {
    NSInteger count = [DisruptionsViewController countInCollection:[DisruptionsViewController collectFromStops:self.stops]];
    if (count == self.bannerCount) return;
    self.bannerCount = count;
    [self buildHeaderAccessory];
}

- (void)openDisruptions {
    DisruptionsViewController *vc = [[DisruptionsViewController alloc]
        initWithStops:[DisruptionsViewController collectFromStops:self.stops]];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showMessage:(NSString *)text {
    if (!text) { [self showEmptyIcon:nil title:nil text:nil]; return; }
    [self showEmptyIcon:@"🚏" title:nil text:text];
}

#pragma mark - Ansage & Schütteln

- (void)announceStop:(NSDictionary *)stop {
    if ([BVGAPI isSpeaking]) { [BVGAPI stopSpeaking]; return; }
    [BVGAPI speak:[BVGAPI announcementForStop:stop[@"name"] departures:stop[@"departures"] max:3]];
}

- (void)announceNearest {
    if (!self.stops.count) return;
    // naechstgelegene Haltestelle = kleinste Entfernung, sonst erste
    NSDictionary *best = self.stops.firstObject;
    for (NSDictionary *s in self.stops) {
        if (s[@"distance"] && (!best[@"distance"] || [s[@"distance"] doubleValue] < [best[@"distance"] doubleValue])) best = s;
    }
    [self announceStop:best];
}

// Haltestellen-Kopf gedrueckt halten -> Ansage fuer diese Haltestelle
- (void)longPress:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:[press locationInView:self.tableView]];
    if (ip && ip.row == 0 && ip.section < (NSInteger)self.stops.count) [self announceStop:self.stops[ip.section]];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self becomeFirstResponder];
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion != UIEventSubtypeMotionShake) return;
    [self.refreshControl beginRefreshing];
    [self refresh];
}

#pragma mark - Favoriten

- (void)favoritesChanged {
    for (NSMutableDictionary *e in self.stops) e[@"fav"] = @([BVGAPI isFavorite:e[@"id"]]);
    NSMutableArray *favs = [NSMutableArray array];
    NSMutableArray *rest = [NSMutableArray array];
    for (NSMutableDictionary *e in self.stops) [([e[@"fav"] boolValue] ? favs : rest) addObject:e];
    [favs addObjectsFromArray:rest];
    self.stops = favs;
    [self.tableView reloadData];
}

- (void)toggleFavorite:(UIButton *)sender {
    if (sender.tag >= (NSInteger)self.stops.count) return;
    NSDictionary *stop = self.stops[sender.tag];
    [BVGAPI setFavorite:![stop[@"fav"] boolValue] stopId:stop[@"id"] name:stop[@"name"]];
}

- (void)openStop:(NSDictionary *)stop {
    StopViewController *vc = [[StopViewController alloc] initWithStopId:stop[@"id"] name:stop[@"name"]];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Laden

- (void)refresh {
    if (self.loading) return;
    self.loading = YES;

    CLAuthorizationStatus st = [CLLocationManager authorizationStatus];
    if (st == kCLAuthorizationStatusAuthorizedWhenInUse || st == kCLAuthorizationStatusAuthorizedAlways) {
        self.waitingForLocation = YES;
        [self.locationManager requestLocation];
    } else {
        [self loadNearby:nil];
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status != kCLAuthorizationStatusNotDetermined) [self refresh];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (!self.waitingForLocation) return;
    self.waitingForLocation = NO;
    [self loadNearby:locations.lastObject];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"Location-Fehler: %@", error);
    if (!self.waitingForLocation) return;
    self.waitingForLocation = NO;
    [self loadNearby:nil];
}

- (void)loadNearby:(CLLocation *)loc {
    if (!loc) {
        [self loadDeparturesWithNearby:@[] hadLocation:NO nearbyFailed:NO];
        return;
    }
    NSString *path = [NSString stringWithFormat:
        @"/locations/nearby?latitude=%.6f&longitude=%.6f&results=6&distance=%ld&poi=false&addresses=false",
        loc.coordinate.latitude, loc.coordinate.longitude, (long)[BVGSettings radius]];
    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        BOOL failed = ![json isKindOfClass:[NSArray class]];
        if (failed) NSLog(@"Nearby-Fehler: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadDeparturesWithNearby:(failed ? @[] : json) hadLocation:YES nearbyFailed:failed];
        });
    }];
}

- (void)loadDeparturesWithNearby:(NSArray *)nearby hadLocation:(BOOL)hadLocation nearbyFailed:(BOOL)nearbyFailed {
    // alte Daten merken: bei Funkloch bleiben sie stehen statt zu verschwinden
    NSMutableDictionary *oldById = [NSMutableDictionary dictionary];
    for (NSDictionary *s in self.stops) if (s[@"id"]) oldById[s[@"id"]] = s;

    NSMutableArray *list = [NSMutableArray array];
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];

    for (NSDictionary *f in [BVGAPI favorites]) {
        NSMutableDictionary *e = [@{ @"id": f[@"id"], @"name": f[@"name"], @"fav": @YES } mutableCopy];
        if (oldById[f[@"id"]][@"distance"]) e[@"distance"] = oldById[f[@"id"]][@"distance"];
        [list addObject:e];
        byId[f[@"id"]] = e;
    }
    // Umgebung nicht ladbar -> bisherige Haltestellen weiterverwenden
    NSArray *source = nearbyFailed ? self.stops : nearby;
    for (NSDictionary *n in source) {
        NSString *sid = NN(n[@"id"]);
        if (!sid || [n[@"fav"] boolValue]) continue;
        NSNumber *dist = NN(n[@"distance"]) ?: @0;
        if (byId[sid]) { byId[sid][@"distance"] = dist; continue; }
        NSMutableDictionary *e = [@{ @"id": sid, @"name": NN(n[@"name"]) ?: @"?", @"distance": dist, @"fav": @NO } mutableCopy];
        [list addObject:e];
        byId[sid] = e;
    }

    if (!list.count) {
        self.stops = @[];
        self.offline = nearbyFailed;
        [self.tableView reloadData];
        if (nearbyFailed) {
            [self showEmptyIcon:@"📡" title:@"Keine Verbindung" text:@"Zum Wiederholen nach unten ziehen oder das iPhone schütteln."];
        } else if (hadLocation) {
            [self showEmptyIcon:@"🔍" title:@"Nichts in der Nähe"
                           text:[NSString stringWithFormat:@"Keine Haltestellen im Umkreis von %ld m. Den Radius kannst du unter „Mehr“ vergrößern.", (long)[BVGSettings radius]]];
        } else {
            [self showEmptyIcon:@"📍" title:@"Kein Standort"
                           text:@"Erlaube den Standortzugriff in den iOS-Einstellungen oder suche oben eine Haltestelle und merke sie dir mit ☆."];
        }
        [self finish];
        return;
    }

    __block BOOL anyFailed = nearbyFailed;
    NSInteger perStop = [BVGSettings departuresPerStop];
    dispatch_group_t group = dispatch_group_create();
    for (NSMutableDictionary *entry in list) {
        dispatch_group_enter(group);
        NSString *path = [NSString stringWithFormat:@"/stops/%@/departures?duration=45&results=%ld",
                          entry[@"id"], (long)(perStop + 6)];
        NSArray *old = oldById[entry[@"id"]][@"departures"];
        [BVGAPI getJSON:path completion:^(id json, NSError *error) {
            NSArray *deps = nil;
            if ([json isKindOfClass:[NSDictionary class]] && [json[@"departures"] isKindOfClass:[NSArray class]]) {
                deps = json[@"departures"];
            }
            @synchronized (entry) {
                if (deps) entry[@"departures"] = deps;
                else {
                    entry[@"departures"] = old ?: @[];   // Fehler: alte Abfahrten behalten
                    anyFailed = YES;
                }
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        self.stops = list;
        self.offline = anyFailed;
        if (!anyFailed) {
            self.dataTime = [NSDate date];
            [self saveCache];
        }
        [self showMessage:nil];
        [self updateStatusHeader];
        [self updateDisruptionBanner];
        [self.tableView reloadData];
        [self finish];
    });
}

- (void)finish {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.loading = NO;
        [self.refreshControl endRefreshing];
        [self updateStatusHeader];
    });
}

#pragma mark - Helfer

- (NSArray *)departuresInSection:(NSInteger)section {
    if (section >= (NSInteger)self.stops.count) return @[];
    NSArray *deps = self.stops[section][@"departures"] ?: @[];
    // gemerkter Richtungsfilter dieser Haltestelle
    NSString *dir = [BVGSettings directionFilterForStop:self.stops[section][@"id"]];
    if (dir) {
        NSMutableArray *f = [NSMutableArray array];
        for (NSDictionary *d in deps) if ([NN(d[@"direction"]) isEqualToString:dir]) [f addObject:d];
        deps = f;
    }
    NSUInteger max = (NSUInteger)[BVGSettings departuresPerStop];
    return deps.count > max ? [deps subarrayWithRange:NSMakeRange(0, max)] : deps;
}

// Zeilen pro Karte: 0 = Haltestelle · 1..n = Abfahrten (oder Leer-Hinweis) · letzte = "Alle Abfahrten"
- (NSDictionary *)departureAt:(NSIndexPath *)ip {
    NSArray *deps = [self departuresInSection:ip.section];
    NSInteger i = ip.row - 1;
    return (i >= 0 && i < (NSInteger)deps.count) ? deps[i] : nil;
}

- (BOOL)isHeaderRow:(NSIndexPath *)ip {
    return ip.row == 0;
}

- (BOOL)isMoreRow:(NSIndexPath *)ip {
    return ip.row == [self tableView:self.tableView numberOfRowsInSection:ip.section] - 1;
}

// Luftlinie * 1,3 (Umwege) bei ca. 80 m/min Gehtempo, mindestens 1 min
- (NSInteger)walkMinutesToStop:(NSDictionary *)stop {
    double dist = [stop[@"distance"] doubleValue];
    return MAX(1, (NSInteger)ceil(dist * 1.3 / 80.0));
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.stops.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 4 : 12;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [[UIView alloc] initWithFrame:CGRectZero];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1 + MAX([self departuresInSection:section].count, 1) + 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isHeaderRow:indexPath]) return 48;
    if ([self isMoreRow:indexPath]) return 40;
    return [DepartureCell height];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *stop = self.stops[indexPath.section];

    if ([self isHeaderRow:indexPath]) {
        StopHeaderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stop"];
        if (!cell) {
            cell = [[StopHeaderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"stop"];
            [cell.starButton addTarget:self action:@selector(toggleFavorite:) forControlEvents:UIControlEventTouchUpInside];
        }
        BOOL fav = [stop[@"fav"] boolValue];
        cell.nameLabel.text = [BVGAPI shortName:stop[@"name"]];
        NSMutableArray *parts = [NSMutableArray array];
        if (stop[@"distance"]) [parts addObject:[NSString stringWithFormat:@"%@ m · %ld min zu Fuß",
                                                 stop[@"distance"], (long)[self walkMinutesToStop:stop]]];
        else if (fav) [parts addObject:@"Favorit"];
        NSString *dirFilter = [BVGSettings directionFilterForStop:stop[@"id"]];
        if (dirFilter) [parts addObject:[@"nur → " stringByAppendingString:dirFilter]];
        cell.metaLabel.text = [parts componentsJoinedByString:@" · "];
        cell.starButton.tag = indexPath.section;
        [cell.starButton setTitle:(fav ? @"★" : @"☆") forState:UIControlStateNormal];
        [cell.starButton setTitleColor:(fav ? [BVGTheme orange] : [BVGTheme textTertiary]) forState:UIControlStateNormal];
        cell.starButton.accessibilityLabel = fav ? @"Favorit entfernen" : @"Als Favorit merken";
        cell.accessibilityLabel = stop[@"name"];
        cell.accessibilityHint = @"Doppeltippen für alle Abfahrten";
        cell.accessibilityTraits = UIAccessibilityTraitHeader | UIAccessibilityTraitButton;
        return cell;
    }

    if ([self isMoreRow:indexPath]) {
        CardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"more"];
        if (!cell) cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"more"];
        cell.textLabel.text = @"Alle Abfahrten";
        cell.textLabel.font = [BVGTheme font:14 weight:UIFontWeightRegular];
        cell.textLabel.textColor = [BVGTheme link];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    DepartureCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dep"];
    if (!cell) cell = [[DepartureCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"dep"];
    NSDictionary *d = [self departureAt:indexPath];
    if (d) {
        [cell configureWithDeparture:d];
        // zu Fuss nicht mehr erreichbar? -> ausgrauen
        NSDate *when = [BVGAPI whenOfDeparture:d];
        BOOL tooLate = stop[@"distance"] && when &&
                       [when timeIntervalSinceNow] / 60.0 < [self walkMinutesToStop:stop];
        [cell setDimmed:tooLate];
    } else {
        [cell configureEmpty:@"Keine Abfahrten in den nächsten 45 min"];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section >= (NSInteger)self.stops.count) return;

    if ([self isHeaderRow:indexPath] || [self isMoreRow:indexPath]) {
        [self openStop:self.stops[indexPath.section]];
        return;
    }

    NSDictionary *d = [self departureAt:indexPath];
    NSString *tripId = NN(d[@"tripId"]);
    if (!tripId) return;

    TripViewController *trip = [[TripViewController alloc] initWithTripId:tripId];
    trip.line = NN(d[@"line"]);
    trip.stopName = self.stops[indexPath.section][@"name"];
    [self.navigationController pushViewController:trip animated:YES];
}

#pragma mark - Wischen → Wecker

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isHeaderRow:indexPath] || [self isMoreRow:indexPath]) return NO;
    NSDictionary *d = [self departureAt:indexPath];
    return d && NN(d[@"tripId"]) && ![NN(d[@"cancelled"]) boolValue];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                            forRowAtIndexPath:(NSIndexPath *)indexPath {
}

- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [BVGAPI editActionsForDeparture:[self departureAt:indexPath]
                                  stopName:self.stops[indexPath.section][@"name"]
                                      from:self];
}

@end
