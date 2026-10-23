#import "StopViewController.h"
#import "TripViewController.h"
#import "DepartureCell.h"
#import "BVGAPI.h"
#import "ChipBar.h"
#import "BVGSettings.h"

@interface StopViewController ()
@property (nonatomic, copy) NSString *stopId;
@property (nonatomic, copy) NSString *stopName;
@property (nonatomic, strong) NSArray *allDepartures;
@property (nonatomic, strong) NSArray *departures;   // gefiltert
@property (nonatomic, strong) NSArray *warnings;     // [{summary, text}]
@property (nonatomic, strong) ChipBar *filter;
@property (nonatomic, strong) UIButton *directionButton;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation StopViewController

- (instancetype)initWithStopId:(NSString *)stopId name:(NSString *)name {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _stopId = [stopId copy];
        _stopName = [name copy];
        _allDepartures = @[];
        _departures = @[];
        _warnings = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = [DepartureCell height];

    // grosser Titel = Haltestellenname, darunter Filter-Chips
    __weak StopViewController *weakSelf = self;
    self.filter = [[ChipBar alloc] initWithItems:@[@"Alle", @"S-Bahn", @"U-Bahn", @"Tram", @"Bus", @"Regio"]];
    self.filter.onChange = ^(NSInteger idx) { [weakSelf applyFilter]; };

    // darunter: Richtungsfilter (wird pro Haltestelle gemerkt, gilt auch in der Startansicht)
    UIView *acc = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 82)];
    [acc addSubview:self.filter];
    self.directionButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.directionButton.frame = CGRectMake([BVGTheme cardInset] + 4, 46, acc.bounds.size.width - 2 * [BVGTheme cardInset] - 8, 32);
    self.directionButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.directionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.directionButton.titleLabel.font = [BVGTheme font:15 weight:UIFontWeightMedium];
    self.directionButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.directionButton addTarget:self action:@selector(chooseDirection) forControlEvents:UIControlEventTouchUpInside];
    [acc addSubview:self.directionButton];
    [self updateDirectionButton];
    self.headerAccessory = acc;
    self.largeSubtitle = @"Nächste 60 Minuten";
    self.largeTitle = self.stopName;

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];

    [self updateStar];
    [[NSNotificationCenter defaultCenter] addObserver:self.tableView selector:@selector(reloadData)
                                                 name:BVGAlarmsChangedNotification object:nil];
    [BVGAPI addRecentStop:self.stopId name:self.stopName];   // + Spotlight
    [self load];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.tableView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(load) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

#pragma mark - Favorit

- (void)updateStar {
    BOOL fav = [BVGAPI isFavorite:self.stopId];
    UIBarButtonItem *star = [[UIBarButtonItem alloc] initWithTitle:(fav ? @"★" : @"☆")
                                                             style:UIBarButtonItemStylePlain
                                                            target:self action:@selector(toggleStar)];
    [star setTitleTextAttributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:24] } forState:UIControlStateNormal];

    star.tintColor = fav ? [BVGTheme orange] : [BVGTheme textSecondary];
    UIBarButtonItem *speaker = [[UIBarButtonItem alloc] initWithTitle:@"Ansage"
                                                                style:UIBarButtonItemStylePlain
                                                               target:self action:@selector(announce)];
    self.navigationItem.rightBarButtonItems = @[star, speaker];
}

- (void)announce {
    if ([BVGAPI isSpeaking]) { [BVGAPI stopSpeaking]; return; }
    [BVGAPI speak:[BVGAPI announcementForStop:self.stopName departures:self.departures max:4]];
}

- (void)toggleStar {
    [BVGAPI setFavorite:![BVGAPI isFavorite:self.stopId] stopId:self.stopId name:self.stopName];
    [self updateStar];
}

#pragma mark - Laden

- (void)load {
    NSString *path = [NSString stringWithFormat:@"/stops/%@/departures?duration=60&results=50", self.stopId];
    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        NSArray *deps = nil;
        if ([json isKindOfClass:[NSDictionary class]] && [json[@"departures"] isKindOfClass:[NSArray class]]) {
            deps = json[@"departures"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.refreshControl endRefreshing];
            if (!deps) {
                NSLog(@"Stop-Fehler: %@", error);
                if (!self.loaded) [self showMessage:@"Abfahrten konnten nicht geladen werden.\nZum Aktualisieren nach unten ziehen."];
                return;
            }
            self.loaded = YES;
            self.allDepartures = deps;
            self.warnings = [self collectWarnings:deps];
            [self applyFilter];
        });
    }];
}

- (NSArray *)collectWarnings:(NSArray *)deps {
    NSMutableArray *list = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *d in deps) {
        id remarks = NN(d[@"remarks"]);
        if (![remarks isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *r in remarks) {
            if (![r isKindOfClass:[NSDictionary class]] || ![NN(r[@"type"]) isEqualToString:@"warning"]) continue;
            NSString *summary = NN(r[@"summary"]) ?: @"Hinweis";
            NSString *text = NN(r[@"text"]) ?: @"";
            NSString *key = [summary stringByAppendingString:text];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [list addObject:@{ @"summary": summary, @"text": text }];
        }
    }
    return list;
}

#pragma mark - Richtung

- (void)updateDirectionButton {
    NSString *dir = [BVGSettings directionFilterForStop:self.stopId];
    [self.directionButton setTitle:(dir ? [NSString stringWithFormat:@"Nur Richtung %@  ✕", dir] : @"Alle Richtungen  ▾")
                          forState:UIControlStateNormal];
    [self.directionButton setTitleColor:(dir ? [BVGTheme orange] : [BVGTheme link]) forState:UIControlStateNormal];
}

- (void)chooseDirection {
    // gesetzter Filter: Antippen hebt ihn auf
    if ([BVGSettings directionFilterForStop:self.stopId]) {
        [BVGSettings setDirectionFilter:nil forStop:self.stopId];
        [self updateDirectionButton];
        [self applyFilter];
        return;
    }
    // Richtungen nach Haeufigkeit sortiert anbieten
    NSCountedSet *counts = [NSCountedSet set];
    for (NSDictionary *d in self.allDepartures) if (NN(d[@"direction"])) [counts addObject:d[@"direction"]];
    NSArray *dirs = [counts.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [@([counts countForObject:b]) compare:@([counts countForObject:a])];
    }];
    if (!dirs.count) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Nur eine Richtung anzeigen"
                                                                   message:@"Wird für diese Haltestelle gemerkt – auch in der Startansicht."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *dir in [dirs subarrayWithRange:NSMakeRange(0, MIN(dirs.count, 8))]) {
        [sheet addAction:[UIAlertAction actionWithTitle:dir style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [BVGSettings setDirectionFilter:dir forStop:self.stopId];
            [self updateDirectionButton];
            [self applyFilter];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)applyFilter {
    NSArray *products = @[@"", @"suburban", @"subway", @"tram", @"bus", @"regional"];
    NSString *want = products[self.filter.selectedIndex];
    NSString *dir = [BVGSettings directionFilterForStop:self.stopId];
    NSMutableArray *f = [NSMutableArray array];
    for (NSDictionary *d in self.allDepartures) {
        if (want.length && ![NN(NN(d[@"line"])[@"product"]) isEqualToString:want]) continue;
        if (dir && ![NN(d[@"direction"]) isEqualToString:dir]) continue;
        [f addObject:d];
    }
    self.departures = f;
    [self showEmptyIcon:nil title:nil text:nil];
    [self.tableView reloadData];
}

- (void)showMessage:(NSString *)text {
    [self showEmptyIcon:@"📡" title:@"Keine Daten" text:text];
}

+ (NSString *)stripHTML:(NSString *)s {
    if (!s) return @"";
    NSString *t = [s stringByReplacingOccurrencesOfString:@"<br */?>" withString:@"\n"
                                                  options:NSRegularExpressionSearch | NSCaseInsensitiveSearch
                                                    range:NSMakeRange(0, s.length)];
    t = [t stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@""
                                        options:NSRegularExpressionSearch range:NSMakeRange(0, t.length)];
    return [t stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return self.warnings.count ? @"Hinweise" : nil;
    return (self.loaded && self.warnings.count) ? @"Abfahrten" : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.warnings.count;
    return self.loaded ? MAX(self.departures.count, 1) : 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? 52 : [DepartureCell height];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        CardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"warn"];
        if (!cell) cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"warn"];
        cell.textLabel.text = [@"⚠︎  " stringByAppendingString:self.warnings[indexPath.row][@"summary"]];
        cell.textLabel.font = [BVGTheme font:15 weight:UIFontWeightMedium];
        cell.textLabel.textColor = [UIColor colorWithRed:0.62 green:0.36 blue:0 alpha:1];
        cell.textLabel.numberOfLines = 2;
        cell.cardColor = [BVGTheme accentSoft];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    DepartureCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dep"];
    if (!cell) cell = [[DepartureCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"dep"];
    if (self.departures.count == 0) {
        [cell configureEmpty:@"Keine Abfahrten für diesen Filter"];
    } else {
        [cell configureWithDeparture:self.departures[indexPath.row]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        NSDictionary *w = self.warnings[indexPath.row];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:w[@"summary"]
                                                                   message:[StopViewController stripHTML:w[@"text"]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    if (indexPath.row >= (NSInteger)self.departures.count) return;
    NSDictionary *d = self.departures[indexPath.row];
    NSString *tripId = NN(d[@"tripId"]);
    if (!tripId) return;

    TripViewController *trip = [[TripViewController alloc] initWithTripId:tripId];
    trip.line = NN(d[@"line"]);
    trip.stopName = self.stopName;
    [self.navigationController pushViewController:trip animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1 || indexPath.row >= (NSInteger)self.departures.count) return NO;
    NSDictionary *d = self.departures[indexPath.row];
    return NN(d[@"tripId"]) && ![NN(d[@"cancelled"]) boolValue];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                            forRowAtIndexPath:(NSIndexPath *)indexPath {
}

- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [BVGAPI editActionsForDeparture:self.departures[indexPath.row] stopName:self.stopName from:self];
}

@end
