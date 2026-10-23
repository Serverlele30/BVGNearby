#import "JourneyViewController.h"
#import "JourneyDetailViewController.h"
#import "SearchViewController.h"
#import "GuidanceManager.h"
#import "GuidanceViewController.h"
#import "BVGAPI.h"
#import "BVGSettings.h"
#import "ChipBar.h"
#import <CoreLocation/CoreLocation.h>

#pragma mark - Zelle fuer eine Verbindung

@interface JourneyCell : CardCell
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIImageView *linesView;
@property (nonatomic, strong) UILabel *infoLabel;
@end

@implementation JourneyCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [BVGTheme digits:20 weight:UIFontWeightSemibold];
        _timeLabel.textColor = [BVGTheme textPrimary];
        [self.contentView addSubview:_timeLabel];

        _durationLabel = [[UILabel alloc] init];
        _durationLabel.font = [BVGTheme digits:15 weight:UIFontWeightSemibold];
        _durationLabel.textColor = [BVGTheme textSecondary];
        _durationLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_durationLabel];

        _linesView = [[UIImageView alloc] init];
        _linesView.contentMode = UIViewContentModeLeft;
        [self.contentView addSubview:_linesView];

        _infoLabel = [[UILabel alloc] init];
        _infoLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
        _infoLabel.textColor = [BVGTheme textSecondary];
        [self.contentView addSubview:_infoLabel];

        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    self.timeLabel.frame     = CGRectMake(16, 10, w - 110, 24);
    self.durationLabel.frame = CGRectMake(w - 96, 10, 84, 24);
    self.linesView.frame     = CGRectMake(16, 38, w - 28, 24);
    self.infoLabel.frame     = CGRectMake(16, 66, w - 28, 17);
}

@end

#pragma mark - Routenplaner

@interface JourneyViewController () <CLLocationManagerDelegate>
@property (nonatomic, strong) NSDictionary *from;      // nil = Mein Standort, sonst {id, name}
@property (nonatomic, strong) NSDictionary *to;
@property (nonatomic, strong) ChipBar *timeControl;   // Jetzt / Abfahrt um / Ankunft um
@property (nonatomic, strong) UIDatePicker *datePicker;
@property (nonatomic, strong) NSArray *journeys;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) BOOL searching;
@property (nonatomic, copy) NSString *errorText;
@end

@implementation JourneyViewController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.largeTitle = @"Route";
    self.largeSubtitle = [NSString stringWithFormat:@"Umstiege mit mind. %ld min Puffer", (long)[BVGSettings transferMinutes]];
    self.journeys = @[];

    __weak JourneyViewController *weakSelf = self;
    self.timeControl = [[ChipBar alloc] initWithItems:@[@"Jetzt", @"Abfahrt um", @"Ankunft um"]];
    self.timeControl.idleColor = [BVGTheme background];
    self.timeControl.onChange = ^(NSInteger idx) { [weakSelf timeModeChanged]; };

    self.datePicker = [[UIDatePicker alloc] init];
    self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
    self.datePicker.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    self.datePicker.minuteInterval = 1;
    self.datePicker.date = [NSDate dateWithTimeIntervalSinceNow:15 * 60];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateNaviButton)
                                                 name:GuidanceChangedNotification object:nil];
    [self updateNaviButton];
    [self buildQuickPlaces];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged)
                                                 name:BVGSettingsChangedNotification object:nil];

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"⇅"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self action:@selector(swap)];
}

#pragma mark - Schnellziele

- (void)settingsChanged {
    self.largeSubtitle = [NSString stringWithFormat:@"Umstiege mit mind. %ld min Puffer", (long)[BVGSettings transferMinutes]];
    [self buildQuickPlaces];
}

- (void)buildQuickPlaces {
    CGFloat w = self.view.bounds.size.width;
    CGFloat inset = [BVGTheme cardInset];
    CGFloat bw = (w - 2 * inset - 10) / 2;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 74)];

    NSArray *defs = @[@[@"home", @"🏠", @"Nach Hause"], @[@"work", @"💼", @"Zur Arbeit"]];
    for (NSUInteger i = 0; i < defs.count; i++) {
        NSDictionary *place = [BVGSettings placeForKey:defs[i][0]];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(inset + i * (bw + 10), 4, bw, 64);
        b.autoresizingMask = i == 0 ? UIViewAutoresizingFlexibleRightMargin : UIViewAutoresizingFlexibleLeftMargin;
        b.backgroundColor = [BVGTheme card];
        b.layer.cornerRadius = [BVGTheme cardRadius];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 10);
        b.titleLabel.numberOfLines = 2;
        b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        b.tag = i;

        NSMutableAttributedString *t = [[NSMutableAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@ %@\n", defs[i][1], defs[i][2]]
                attributes:@{ NSFontAttributeName: [BVGTheme font:16 weight:UIFontWeightSemibold],
                              NSForegroundColorAttributeName: [BVGTheme textPrimary] }];
        [t appendAttributedString:[[NSAttributedString alloc] initWithString:(place ? place[@"name"] : @"Festlegen …")
            attributes:@{ NSFontAttributeName: [BVGTheme font:13 weight:UIFontWeightRegular],
                          NSForegroundColorAttributeName: place ? [BVGTheme textSecondary] : [BVGTheme link] }]];
        [b setAttributedTitle:t forState:UIControlStateNormal];
        [b addTarget:self action:@selector(quickPlaceTapped:) forControlEvents:UIControlEventTouchUpInside];
        [b addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(quickPlaceLongPress:)]];
        b.accessibilityHint = @"Gedrückt halten zum Ändern";
        [v addSubview:b];
    }
    self.headerAccessory = v;
}

- (NSString *)quickKey:(NSInteger)idx {
    return idx == 0 ? @"home" : @"work";
}

- (void)quickPlaceTapped:(UIButton *)b {
    NSDictionary *place = [BVGSettings placeForKey:[self quickKey:b.tag]];
    if (!place) { [self editQuickPlace:b.tag]; return; }
    self.from = nil;           // ab meinem Standort
    self.to = place;
    self.timeControl.selectedIndex = 0;
    [self.tableView reloadData];
    [self startSearch];
}

- (void)quickPlaceLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) [self editQuickPlace:g.view.tag];
}

- (void)editQuickPlace:(NSInteger)idx {
    NSString *key = [self quickKey:idx];
    __weak JourneyViewController *weakSelf = self;
    SearchViewController *search = [[SearchViewController alloc] initWithStyle:UITableViewStylePlain];
    search.allowAddresses = YES;
    search.pickHandler = ^(NSDictionary *place) {
        [BVGSettings setPlace:place forKey:key];
        [weakSelf buildQuickPlaces];
    };
    [self.navigationController pushViewController:search animated:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateNaviButton {
    self.navigationItem.rightBarButtonItem = [GuidanceManager shared].active
        ? [[UIBarButtonItem alloc] initWithTitle:@"Navigation" style:UIBarButtonItemStyleDone target:self action:@selector(openGuidance)]
        : nil;
}

- (void)openGuidance {
    [self.navigationController pushViewController:[[GuidanceViewController alloc] initWithStyle:UITableViewStyleGrouped]
                                         animated:YES];
}

- (void)timeModeChanged {
    if (self.timeControl.selectedIndex > 0 && [self.datePicker.date timeIntervalSinceNow] < -3600) {
        self.datePicker.date = [NSDate dateWithTimeIntervalSinceNow:15 * 60];
    }
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)swap {
    if (!self.to) return;
    NSDictionary *oldFrom = self.from;
    self.from = self.to;
    self.to = oldFrom;   // nil (Mein Standort) als Ziel ist nicht erlaubt -> unten abgefangen
    if (!self.to) {
        self.to = self.from;
        self.from = nil;
    }
    self.journeys = @[];
    [self.tableView reloadData];
}

#pragma mark - Auswahl

- (void)chooseEndpoint:(BOOL)isFrom {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:(isFrom ? @"Start" : @"Ziel")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak JourneyViewController *weakSelf = self;
    if (isFrom) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"📍 Mein Standort" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { weakSelf.from = nil; [weakSelf.tableView reloadData]; }]];
    }
    for (NSArray *pl in @[@[@"home", @"🏠 "], @[@"work", @"💼 "]]) {
        NSDictionary *place = [BVGSettings placeForKey:pl[0]];
        if (!place) continue;
        [sheet addAction:[UIAlertAction actionWithTitle:[pl[1] stringByAppendingString:place[@"name"]] style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { [weakSelf setEndpoint:place isFrom:isFrom]; }]];
    }
    NSInteger n = 0;
    for (NSDictionary *f in [BVGAPI favorites]) {
        if (n++ >= 4) break;
        [sheet addAction:[UIAlertAction actionWithTitle:[@"★ " stringByAppendingString:f[@"name"]] style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { [weakSelf setEndpoint:f isFrom:isFrom]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"🔍 Haltestelle oder Adresse suchen …" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        SearchViewController *search = [[SearchViewController alloc] initWithStyle:UITableViewStylePlain];
        search.allowAddresses = YES;
        search.pickHandler = ^(NSDictionary *stop) { [weakSelf setEndpoint:stop isFrom:isFrom]; };
        [weakSelf.navigationController pushViewController:search animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)setEndpoint:(NSDictionary *)stop isFrom:(BOOL)isFrom {
    if (isFrom) self.from = stop; else self.to = stop;
    self.journeys = @[];
    self.errorText = nil;
    [self.tableView reloadData];
}

#pragma mark - Suche

+ (NSString *)param:(NSString *)prefix place:(NSDictionary *)place {
    if (place[@"id"]) return [NSString stringWithFormat:@"%@=%@", prefix, [BVGAPI encode:place[@"id"]]];
    return [NSString stringWithFormat:@"%@.latitude=%f&%@.longitude=%f&%@.address=%@",
            prefix, [place[@"latitude"] doubleValue], prefix, [place[@"longitude"] doubleValue],
            prefix, [BVGAPI encode:place[@"name"] ?: @"Ort"]];
}

- (void)startSearch {
    if (!self.to) { [self chooseEndpoint:NO]; return; }
    if (self.searching) return;
    self.searching = YES;
    self.errorText = nil;
    self.journeys = @[];
    [self.tableView reloadData];

    if (self.from) {
        [self queryWithFromParams:[JourneyViewController param:@"from" place:self.from]];
        return;
    }
    CLAuthorizationStatus st = [CLLocationManager authorizationStatus];
    if (st == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    [self.locationManager requestLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (!self.searching) return;
    CLLocationCoordinate2D c = locations.lastObject.coordinate;
    [self queryWithFromParams:[NSString stringWithFormat:@"from.latitude=%.6f&from.longitude=%.6f&from.address=%@",
                               c.latitude, c.longitude, [BVGAPI encode:@"Mein Standort"]]];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (!self.searching) return;
    self.searching = NO;
    self.errorText = @"Standort nicht verfügbar. Wähle eine Start-Haltestelle.";
    [self.tableView reloadData];
}

- (void)queryWithFromParams:(NSString *)fromParams {
    // stopovers=true: noetig fuer die Aussteige-Erinnerung in der Navigation
    NSMutableString *path = [NSMutableString stringWithFormat:@"/journeys?%@&%@&results=5&stopovers=true&remarks=true&transferTime=%ld",
                             fromParams, [JourneyViewController param:@"to" place:self.to], (long)[BVGSettings transferMinutes]];
    NSInteger mode = self.timeControl.selectedIndex;
    if (mode > 0) {
        [path appendFormat:@"&%@=%@", mode == 1 ? @"departure" : @"arrival",
                           [BVGAPI encode:[BVGAPI isoFromDate:self.datePicker.date]]];
    }

    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        NSArray *list = nil;
        if ([json isKindOfClass:[NSDictionary class]] && [json[@"journeys"] isKindOfClass:[NSArray class]]) list = json[@"journeys"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.searching = NO;
            if (!list) {
                NSLog(@"Journey-Fehler: %@ %@", error, json);
                self.errorText = @"Keine Verbindung gefunden oder Server nicht erreichbar.";
            }
            // Sicherheitsnetz: nur Verbindungen mit mind. 5 min pro Umstieg zeigen
            NSMutableArray *ok = [NSMutableArray array];
            for (NSDictionary *j in list ?: @[]) {
                id legs = NN(j[@"legs"]);
                if ([legs isKindOfClass:[NSArray class]] && [GuidanceManager minTransferSlack:legs] >= [BVGSettings transferMinutes] * 60) [ok addObject:j];
            }
            if (list.count && !ok.count) self.errorText = [NSString stringWithFormat:@"Keine Verbindung mit mind. %ld min Umstiegszeit gefunden.", (long)[BVGSettings transferMinutes]];
            self.journeys = ok;
            [self.tableView reloadData];
        });
    }];
}

#pragma mark - Auswertung einer Verbindung

+ (NSDate *)legDeparture:(NSDictionary *)leg {
    return [BVGAPI dateFromISO:leg[@"departure"]] ?: [BVGAPI dateFromISO:leg[@"plannedDeparture"]];
}

+ (NSDate *)legArrival:(NSDictionary *)leg {
    return [BVGAPI dateFromISO:leg[@"arrival"]] ?: [BVGAPI dateFromISO:leg[@"plannedArrival"]];
}

- (void)configureCell:(JourneyCell *)cell journey:(NSDictionary *)j {
    NSArray *legs = NN(j[@"legs"]);
    if (![legs isKindOfClass:[NSArray class]] || !legs.count) return;

    NSDate *dep = [JourneyViewController legDeparture:legs.firstObject];
    NSDate *arr = [JourneyViewController legArrival:legs.lastObject];
    NSInteger mins = (dep && arr) ? (NSInteger)round([arr timeIntervalSinceDate:dep] / 60.0) : 0;

    NSMutableArray *lines = [NSMutableArray array];
    BOOL cancelled = NO;
    NSInteger firstDelay = -1;
    NSString *firstStop = nil;
    NSDate *firstTransitDep = nil;
    for (NSDictionary *leg in legs) {
        if ([NN(leg[@"cancelled"]) boolValue]) cancelled = YES;
        if ([NN(leg[@"walking"]) boolValue] || !NN(leg[@"line"])) continue;
        [lines addObject:leg[@"line"]];
        if (firstDelay < 0) {
            firstDelay = [NN(leg[@"departureDelay"]) integerValue] / 60;
            firstStop = NN(NN(leg[@"origin"])[@"name"]);
            firstTransitDep = [JourneyViewController legDeparture:leg];
        }
    }

    cell.timeLabel.text = [NSString stringWithFormat:@"%@  →  %@", [BVGAPI hhmm:dep], [BVGAPI hhmm:arr]];
    cell.durationLabel.text = [NSString stringWithFormat:@"%ld min", (long)mins];
    cell.linesView.image = [BVGAPI badgeStripForLines:lines];

    NSMutableArray *info = [NSMutableArray array];
    NSInteger transfers = MAX((NSInteger)lines.count - 1, 0);
    if (transfers == 0) {
        [info addObject:@"direkt"];
    } else {
        NSTimeInterval slack = [GuidanceManager minTransferSlack:legs];
        [info addObject:[NSString stringWithFormat:@"%ld× umsteigen (mind. %ld min)", (long)transfers, (long)floor(slack / 60.0)]];
    }
    if (firstStop && firstTransitDep) {
        NSInteger leave = (NSInteger)floor([firstTransitDep timeIntervalSinceNow] / 60.0);
        [info addObject:leave > 0 ? [NSString stringWithFormat:@"in %ld min ab %@", (long)leave, firstStop]
                                  : [NSString stringWithFormat:@"ab %@", firstStop]];
    }
    if (firstDelay > 0) [info addObject:[NSString stringWithFormat:@"+%ld", (long)firstDelay]];
    if (cancelled) [info addObject:@"⚠ Ausfall"];

    cell.infoLabel.text = [info componentsJoinedByString:@" · "];
    cell.infoLabel.textColor = (cancelled || firstDelay > 0) ? [BVGTheme red] : [BVGTheme textSecondary];
}

#pragma mark - Table

// Abschnitte: 0 Von/Nach · 1 Zeit · 2 Suchen-Knopf · 3+ je eine Karte pro Verbindung
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3 + self.journeys.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"Wann?";
    if (section == 3) return @"Verbindungen";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 2) return nil;
    if (self.searching) return @"Suche Verbindungen …";
    return self.errorText;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return self.timeControl.selectedIndex == 0 ? 1 : 2;
        default: return 1;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return 60;
    if (indexPath.section == 1) return indexPath.row == 1 ? 180 : 56;
    if (indexPath.section == 2) return 52;
    return 94;
}

// kleine runde Markierung: Start gruen gefuellt, Ziel als Ring
+ (UIImage *)endpointIcon:(BOOL)isFrom {
    CGSize size = CGSizeMake(22, 22);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 4, 14, 14)];
    if (isFrom) { [[BVGTheme green] setFill]; [p fill]; }
    else { p.lineWidth = 4; [[BVGTheme red] setStroke]; [p stroke]; }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section >= 3) {
        JourneyCell *cell = [tableView dequeueReusableCellWithIdentifier:@"journey"];
        if (!cell) cell = [[JourneyCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"journey"];
        [self configureCell:cell journey:self.journeys[indexPath.section - 3]];
        return cell;
    }

    CardCell *cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (indexPath.section == 0) {
        BOOL isFrom = indexPath.row == 0;
        cell.imageView.image = [JourneyViewController endpointIcon:isFrom];
        cell.textLabel.font = [BVGTheme font:17 weight:UIFontWeightSemibold];
        if (isFrom) cell.textLabel.text = self.from ? self.from[@"name"] : @"Mein Standort";
        else        cell.textLabel.text = self.to ? self.to[@"name"] : @"Ziel wählen";
        if (!isFrom && !self.to) cell.textLabel.textColor = [BVGTheme link];
        cell.detailTextLabel.text = isFrom ? @"Start" : @"Ziel";
        cell.detailTextLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [self.datePicker removeFromSuperview];
        self.datePicker.frame = CGRectMake(0, 0, tableView.bounds.size.width - 2 * [BVGTheme cardInset], 180);
        self.datePicker.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:self.datePicker];
    } else if (indexPath.section == 1) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [self.timeControl removeFromSuperview];
        self.timeControl.frame = CGRectMake(-[BVGTheme cardInset] + 12, 6, tableView.bounds.size.width - 2 * [BVGTheme cardInset], 44);
        [cell.contentView addSubview:self.timeControl];
    } else {
        cell.textLabel.text = self.searching ? @"Suche …" : @"Verbindungen suchen";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [BVGTheme font:17 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = [BVGTheme textPrimary];
        cell.cardColor = [BVGTheme accent];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        [self chooseEndpoint:(indexPath.row == 0)];
    } else if (indexPath.section == 2) {
        [self startSearch];
    } else if (indexPath.section >= 3) {
        JourneyDetailViewController *vc = [[JourneyDetailViewController alloc] initWithJourney:self.journeys[indexPath.section - 3]];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
