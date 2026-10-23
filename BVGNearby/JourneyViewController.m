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
        _timeLabel.font = [BVGTheme digits:17 weight:UIFontWeightSemibold];
        _timeLabel.textColor = [BVGTheme textPrimary];
        _timeLabel.adjustsFontSizeToFitWidth = YES;
        _timeLabel.minimumScaleFactor = 0.8;
        [self.contentView addSubview:_timeLabel];

        _durationLabel = [[UILabel alloc] init];
        _durationLabel.font = [BVGTheme digits:14 weight:UIFontWeightMedium];
        _durationLabel.textColor = [BVGTheme textSecondary];
        _durationLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_durationLabel];

        _linesView = [[UIImageView alloc] init];
        _linesView.contentMode = UIViewContentModeLeft;
        [self.contentView addSubview:_linesView];

        _infoLabel = [[UILabel alloc] init];
        _infoLabel.font = [BVGTheme font:12 weight:UIFontWeightRegular];
        _infoLabel.textColor = [BVGTheme textSecondary];
        [self.contentView addSubview:_infoLabel];

        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    self.timeLabel.frame     = CGRectMake(14, 9, w - 110, 21);
    self.durationLabel.frame = CGRectMake(w - 92, 10, 84, 19);
    self.linesView.frame     = CGRectMake(14, 34, w - 22, 22);
    self.infoLabel.frame     = CGRectMake(14, 60, w - 22, 15);
}

@end

#pragma mark - Routenplaner

typedef NS_ENUM(NSInteger, JourneySection) {
    JourneySectionDate,      // Datumsauswahl (nur bei "Abfahrt um" / "Ankunft um")
    JourneySectionSearch,    // Suchen-Knopf + Statuszeile
    JourneySectionQuick,     // Schnellziele (wenn noch keine Ergebnisse)
    JourneySectionResult,    // je eine Karte pro Verbindung
};

@interface JourneyViewController () <CLLocationManagerDelegate>
@property (nonatomic, strong) NSDictionary *from;      // nil = Mein Standort, sonst {id, name} oder {name, latitude, longitude}
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
    self.largeTitle = @"Verbindung";
    self.journeys = @[];

    __weak JourneyViewController *weakSelf = self;
    self.timeControl = [[ChipBar alloc] initWithItems:@[@"Jetzt", @"Abfahrt um", @"Ankunft um"]];
    self.timeControl.onChange = ^(NSInteger idx) { [weakSelf timeModeChanged]; };

    self.datePicker = [[UIDatePicker alloc] init];
    self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
    self.datePicker.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    self.datePicker.minuteInterval = 1;
    self.datePicker.date = [NSDate dateWithTimeIntervalSinceNow:15 * 60];

    [self buildHeader];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(updateNaviButton) name:GuidanceChangedNotification object:nil];
    [nc addObserver:self selector:@selector(settingsChanged) name:BVGSettingsChangedNotification object:nil];
    [self updateNaviButton];

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)settingsChanged {
    [self.tableView reloadData];
}

#pragma mark - Kopfbereich: Von / Nach + Zeit

- (UIButton *)endpointButton:(BOOL)isFrom frame:(CGRect)frame {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 8);
    [b setBackgroundImage:[BVGTheme imageWithColor:[BVGTheme cardPressed]] forState:UIControlStateHighlighted];
    b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSString *label = isFrom ? @"Von  " : @"Nach  ";
    NSString *value;
    BOOL placeholder = NO;
    if (isFrom) value = self.from ? [BVGAPI shortName:self.from[@"name"]] : @"Mein Standort";
    else if (self.to) value = [BVGAPI shortName:self.to[@"name"]];
    else { value = @"Ziel eingeben"; placeholder = YES; }

    NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:label attributes:@{
        NSFontAttributeName: [BVGTheme font:13 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: [BVGTheme textSecondary] }];
    [t appendAttributedString:[[NSAttributedString alloc] initWithString:value ?: @"" attributes:@{
        NSFontAttributeName: [BVGTheme font:15 weight:(placeholder ? UIFontWeightRegular : UIFontWeightSemibold)],
        NSForegroundColorAttributeName: placeholder ? [BVGTheme textTertiary] : [BVGTheme textPrimary] }]];
    [b setAttributedTitle:t forState:UIControlStateNormal];
    b.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", isFrom ? @"Start" : @"Ziel", value];
    b.tag = isFrom ? 0 : 1;
    [b addTarget:self action:@selector(endpointTapped:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildHeader {
    CGFloat w = self.view.bounds.size.width;
    CGFloat inset = [BVGTheme cardInset];
    CGFloat cardW = w - 2 * inset;
    CGFloat rowH = 42;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 2 * rowH + 46)];

    // weisse Karte mit zwei Zeilen und Tausch-Knopf rechts
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(inset, 0, cardW, 2 * rowH)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [UIColor whiteColor];
    card.layer.cornerRadius = [BVGTheme cardRadius];
    card.clipsToBounds = YES;
    [v addSubview:card];

    [card addSubview:[self endpointButton:YES frame:CGRectMake(0, 0, cardW - 46, rowH)]];
    [card addSubview:[self endpointButton:NO frame:CGRectMake(0, rowH, cardW - 46, rowH)]];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(12, rowH, cardW - 58, 1.0 / [UIScreen mainScreen].scale)];
    line.backgroundColor = [BVGTheme separator];
    line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card addSubview:line];

    UIButton *swap = [UIButton buttonWithType:UIButtonTypeCustom];
    swap.frame = CGRectMake(cardW - 42, rowH - 16, 32, 32);
    swap.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [swap setBackgroundImage:[BVGTheme roundedImageWithColor:[BVGTheme background] radius:16] forState:UIControlStateNormal];
    [swap setBackgroundImage:[BVGTheme roundedImageWithColor:[BVGTheme cardPressed] radius:16] forState:UIControlStateHighlighted];
    swap.titleLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
    [swap setTitle:@"⇅" forState:UIControlStateNormal];
    [swap setTitleColor:[BVGTheme textPrimary] forState:UIControlStateNormal];
    swap.accessibilityLabel = @"Start und Ziel tauschen";
    [swap addTarget:self action:@selector(swap) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:swap];

    // Zeit-Chips darunter
    [self.timeControl removeFromSuperview];
    self.timeControl.frame = CGRectMake(0, 2 * rowH + 2, w, 44);
    self.timeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:self.timeControl];

    self.headerAccessory = v;
}

- (void)endpointTapped:(UIButton *)b {
    [self chooseEndpoint:(b.tag == 0)];
}

- (void)updateNaviButton {
    self.navigationItem.rightBarButtonItem = [GuidanceManager shared].active
        ? [[UIBarButtonItem alloc] initWithTitle:@"Navigation ›" style:UIBarButtonItemStyleDone target:self action:@selector(openGuidance)]
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
    [self.tableView reloadData];
}

- (void)swap {
    if (!self.to) return;
    NSDictionary *oldFrom = self.from;
    self.from = self.to;
    self.to = oldFrom;   // nil (Mein Standort) als Ziel ist nicht erlaubt
    if (!self.to) {
        self.to = self.from;
        self.from = nil;
    }
    self.journeys = @[];
    self.errorText = nil;
    [self buildHeader];
    [self.tableView reloadData];
}

#pragma mark - Auswahl von Start/Ziel: direkt die Suche mit Schnellauswahl

- (void)chooseEndpoint:(BOOL)isFrom {
    __weak JourneyViewController *weakSelf = self;
    SearchViewController *search = [[SearchViewController alloc] initWithStyle:UITableViewStylePlain];
    search.allowAddresses = YES;
    search.offerSavedPlaces = YES;
    search.offerCurrentLocation = isFrom;
    search.pickTitle = isFrom ? @"Start" : @"Ziel";
    search.pickHandler = ^(NSDictionary *place) {
        if (!isFrom && !place) return;   // "Mein Standort" nur als Start
        [weakSelf setEndpoint:place isFrom:isFrom];
    };
    [self.navigationController pushViewController:search animated:YES];
}

- (void)setEndpoint:(NSDictionary *)place isFrom:(BOOL)isFrom {
    if (isFrom) self.from = place; else self.to = place;
    self.journeys = @[];
    self.errorText = nil;
    [self buildHeader];
    [self.tableView reloadData];
    if (self.to) [self startSearch];   // Ziel steht -> gleich suchen (wie in der BVG-App)
}

#pragma mark - Schnellziele

- (NSString *)quickKey:(NSInteger)idx {
    return idx == 0 ? @"home" : @"work";
}

- (void)quickPlaceTapped:(NSInteger)idx {
    NSDictionary *place = [BVGSettings placeForKey:[self quickKey:idx]];
    if (!place) { [self editQuickPlace:idx]; return; }
    self.from = nil;           // ab meinem Standort
    self.timeControl.selectedIndex = 0;
    [self setEndpoint:place isFrom:NO];
}

- (void)editQuickPlace:(NSInteger)idx {
    NSString *key = [self quickKey:idx];
    __weak JourneyViewController *weakSelf = self;
    SearchViewController *search = [[SearchViewController alloc] initWithStyle:UITableViewStylePlain];
    search.allowAddresses = YES;
    search.pickTitle = idx == 0 ? @"Zuhause festlegen" : @"Arbeit festlegen";
    search.pickHandler = ^(NSDictionary *place) {
        if (!place) return;
        [BVGSettings setPlace:place forKey:key];
        [weakSelf.tableView reloadData];
    };
    [self.navigationController pushViewController:search animated:YES];
}

- (void)quickLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:[g locationInView:self.tableView]];
    if (ip && [self kindOfSection:ip.section] == JourneySectionQuick) [self editQuickPlace:ip.row];
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
    self.errorText = @"Standort nicht verfügbar. Tippe auf „Von“ und wähle eine Haltestelle.";
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
            // Sicherheitsnetz: nur Verbindungen mit mind. X min pro Umstieg zeigen
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

- (void)configureCell:(JourneyCell *)cell journey:(NSDictionary *)j {
    NSArray *legs = NN(j[@"legs"]);
    if (![legs isKindOfClass:[NSArray class]] || !legs.count) return;

    NSDate *dep = [GuidanceManager legDeparture:legs.firstObject];
    NSDate *arr = [GuidanceManager legArrival:legs.lastObject];
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
            firstStop = [BVGAPI shortName:NN(NN(leg[@"origin"])[@"name"])];
            firstTransitDep = [GuidanceManager legDeparture:leg];
        }
    }

    cell.timeLabel.text = [NSString stringWithFormat:@"%@ – %@", [BVGAPI hhmm:dep], [BVGAPI hhmm:arr]];
    cell.durationLabel.text = mins >= 60 ? [NSString stringWithFormat:@"%ld:%02ld h", (long)(mins / 60), (long)(mins % 60)]
                                         : [NSString stringWithFormat:@"%ld min", (long)mins];
    cell.linesView.image = [BVGAPI badgeStripForLines:lines];

    NSMutableArray *info = [NSMutableArray array];
    NSInteger transfers = MAX((NSInteger)lines.count - 1, 0);
    if (transfers == 0) [info addObject:@"direkt"];
    else [info addObject:[NSString stringWithFormat:@"%ld× umsteigen", (long)transfers]];
    if (firstStop && firstTransitDep) {
        NSInteger leave = (NSInteger)floor([firstTransitDep timeIntervalSinceNow] / 60.0);
        [info addObject:leave > 0 ? [NSString stringWithFormat:@"in %ld min ab %@", (long)leave, firstStop]
                                  : [NSString stringWithFormat:@"ab %@", firstStop]];
    }
    UIColor *color = [BVGTheme textSecondary];
    if (firstDelay > 0) { [info insertObject:[NSString stringWithFormat:@"+%ld min", (long)firstDelay] atIndex:0]; color = [BVGTheme red]; }
    if (cancelled) { [info insertObject:@"⚠︎ Ausfall" atIndex:0]; color = [BVGTheme red]; }

    cell.infoLabel.text = [info componentsJoinedByString:@" · "];
    cell.infoLabel.textColor = color;
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@ bis %@, %ld Minuten, %@",
                               [BVGAPI hhmm:dep], [BVGAPI hhmm:arr], (long)mins, cell.infoLabel.text];
}

#pragma mark - Table

- (NSArray *)sectionKinds {
    NSMutableArray *k = [NSMutableArray array];
    if (self.timeControl.selectedIndex > 0) [k addObject:@(JourneySectionDate)];
    [k addObject:@(JourneySectionSearch)];
    if (!self.journeys.count && !self.searching) [k addObject:@(JourneySectionQuick)];
    for (NSUInteger i = 0; i < self.journeys.count; i++) [k addObject:@(JourneySectionResult)];
    return k;
}

- (JourneySection)kindOfSection:(NSInteger)section {
    NSArray *k = [self sectionKinds];
    return section < (NSInteger)k.count ? [k[section] integerValue] : JourneySectionResult;
}

- (NSDictionary *)journeyForSection:(NSInteger)section {
    NSInteger first = [[self sectionKinds] indexOfObject:@(JourneySectionResult)];
    NSInteger i = section - first;
    return (first != NSNotFound && i >= 0 && i < (NSInteger)self.journeys.count) ? self.journeys[i] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self sectionKinds].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    JourneySection kind = [self kindOfSection:section];
    if (kind == JourneySectionQuick) return @"Schnellziele";
    if (kind == JourneySectionResult && section > 0 && [self kindOfSection:section - 1] != JourneySectionResult) {
        return @"Verbindungen";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    JourneySection kind = [self kindOfSection:section];
    if (kind == JourneySectionSearch) {
        if (self.searching) return @"Suche Verbindungen …";
        if (self.errorText) return self.errorText;
        return [NSString stringWithFormat:@"Umstiege immer mit mind. %ld min Puffer.", (long)[BVGSettings transferMinutes]];
    }
    if (kind == JourneySectionQuick) return @"Gedrückt halten zum Ändern.";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self kindOfSection:section] == JourneySectionQuick ? 2 : 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ([self kindOfSection:indexPath.section]) {
        case JourneySectionDate:   return 180;
        case JourneySectionSearch: return 44;
        case JourneySectionQuick:  return 50;
        case JourneySectionResult: return 84;
    }
    return 52;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    JourneySection kind = [self kindOfSection:indexPath.section];

    if (kind == JourneySectionResult) {
        JourneyCell *cell = [tableView dequeueReusableCellWithIdentifier:@"journey"];
        if (!cell) cell = [[JourneyCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"journey"];
        [self configureCell:cell journey:[self journeyForSection:indexPath.section]];
        return cell;
    }

    CardCell *cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (kind == JourneySectionDate) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [self.datePicker removeFromSuperview];
        self.datePicker.frame = CGRectMake(0, 0, tableView.bounds.size.width - 2 * [BVGTheme cardInset], 180);
        self.datePicker.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:self.datePicker];
    } else if (kind == JourneySectionSearch) {
        // dunkler Hauptknopf
        cell.textLabel.text = self.searching ? @"Suche …" : @"Verbindungen suchen";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.cardColor = [BVGTheme textPrimary];
        cell.accessibilityTraits = UIAccessibilityTraitButton;
    } else {
        NSArray *defs = @[@[@"home", @"⌂", @"Nach Hause"], @[@"work", @"✱", @"Zur Arbeit"]];
        NSArray *d = defs[indexPath.row];
        NSDictionary *place = [BVGSettings placeForKey:d[0]];
        cell.imageView.image = [JourneyViewController roundIcon:d[1]];
        cell.textLabel.text = d[2];
        cell.textLabel.font = [BVGTheme font:15 weight:UIFontWeightSemibold];
        cell.detailTextLabel.font = [BVGTheme font:12 weight:UIFontWeightRegular];
        cell.detailTextLabel.text = place ? place[@"name"] : @"Antippen zum Festlegen";
        cell.detailTextLabel.textColor = place ? [BVGTheme textSecondary] : [BVGTheme link];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (!cell.gestureRecognizers.count) {
            [cell addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(quickLongPress:)]];
        }
    }
    return cell;
}

+ (UIImage *)roundIcon:(NSString *)text {
    CGSize size = CGSizeMake(28, 28);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [[BVGTheme accentSoft] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 28, 28)] fill];
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
                             NSForegroundColorAttributeName: [BVGTheme textPrimary] };
    CGSize t = [text sizeWithAttributes:attrs];
    [text drawAtPoint:CGPointMake((28 - t.width) / 2, (28 - t.height) / 2) withAttributes:attrs];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch ([self kindOfSection:indexPath.section]) {
        case JourneySectionSearch: [self startSearch]; break;
        case JourneySectionQuick:  [self quickPlaceTapped:indexPath.row]; break;
        case JourneySectionResult: {
            NSDictionary *j = [self journeyForSection:indexPath.section];
            if (!j) break;
            JourneyDetailViewController *vc = [[JourneyDetailViewController alloc] initWithJourney:j];
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        default: break;
    }
}

@end
