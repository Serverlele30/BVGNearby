#import "JourneyDetailViewController.h"
#import "TripViewController.h"
#import "GuidanceManager.h"
#import "GuidanceViewController.h"
#import "BVGAPI.h"

@interface JourneyDetailViewController ()
@property (nonatomic, strong) NSDictionary *journey;
@property (nonatomic, strong) NSArray *legs;
@end

@implementation JourneyDetailViewController

- (instancetype)initWithJourney:(NSDictionary *)journey {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _journey = journey;
        id legs = NN(journey[@"legs"]);
        _legs = [legs isKindOfClass:[NSArray class]] ? legs : @[];
    }
    return self;
}

+ (BOOL)isWalk:(NSDictionary *)leg { return [GuidanceManager isWalk:leg]; }
+ (NSDate *)dep:(NSDictionary *)leg { return [GuidanceManager legDeparture:leg]; }
+ (NSDate *)arr:(NSDictionary *)leg { return [GuidanceManager legArrival:leg]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Verbindung";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Wecker"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(setAlarm)];

    // Kopf: Zeiten gross, darunter Dauer + Umstiege
    NSDate *dep = [JourneyDetailViewController dep:self.legs.firstObject];
    NSDate *arr = [JourneyDetailViewController arr:self.legs.lastObject];
    NSInteger mins = (dep && arr) ? (NSInteger)round([arr timeIntervalSinceDate:dep] / 60.0) : 0;
    NSInteger transit = 0;
    for (NSDictionary *l in self.legs) if (![JourneyDetailViewController isWalk:l]) transit++;
    self.largeTitle = [NSString stringWithFormat:@"%@ – %@", [BVGAPI hhmm:dep], [BVGAPI hhmm:arr]];
    self.largeSubtitle = [NSString stringWithFormat:@"%ld min  ·  %@", (long)mins,
                          transit <= 1 ? @"ohne Umstieg" : [NSString stringWithFormat:@"%ld× umsteigen", (long)(transit - 1)]];

    // grosser Start-Knopf
    CGFloat w = self.view.bounds.size.width;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 96)];
    UIButton *start = [UIButton buttonWithType:UIButtonTypeCustom];
    start.frame = CGRectMake([BVGTheme cardInset], 16, w - 2 * [BVGTheme cardInset], 46);
    start.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    start.backgroundColor = [BVGTheme textPrimary];
    start.layer.cornerRadius = [BVGTheme cardRadius];
    start.titleLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
    [start setTitle:@"Navigation starten" forState:UIControlStateNormal];
    [start setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [start setTitleColor:[BVGTheme textTertiary] forState:UIControlStateHighlighted];
    [start addTarget:self action:@selector(startGuidance) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:start];
    self.tableView.tableFooterView = footer;
}

- (void)startGuidance {
    void (^go)(void) = ^{
        [[GuidanceManager shared] startWithJourney:self.journey];
        GuidanceViewController *vc = [[GuidanceViewController alloc] initWithStyle:UITableViewStyleGrouped];
        [self.navigationController pushViewController:vc animated:YES];
    };
    if (![GuidanceManager shared].active) { go(); return; }

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Navigation läuft bereits"
                                                               message:@"Die laufende Navigation durch diese Verbindung ersetzen?"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Ersetzen" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { go(); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// Wecker fuer das erste Verkehrsmittel der Verbindung
- (void)setAlarm {
    for (NSDictionary *leg in self.legs) {
        if ([JourneyDetailViewController isWalk:leg] || !NN(leg[@"tripId"])) continue;
        NSDate *dep = [JourneyDetailViewController dep:leg];
        if (!dep) break;
        NSDictionary *pseudoDeparture = @{ @"tripId": leg[@"tripId"],
                                           @"line": leg[@"line"],
                                           @"direction": NN(leg[@"direction"]) ?: @"",
                                           @"when": [BVGAPI isoFromDate:dep] };
        [BVGAPI presentAlarmSheetForDeparture:pseudoDeparture stopName:NN(NN(leg[@"origin"])[@"name"]) from:self];
        return;
    }
}

#pragma mark - Table (ein Abschnitt pro Teilstrecke)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.legs.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    // Umstiegszeit zwischen zwei Fahrten als Abschnittstitel
    if (section == 0 || [JourneyDetailViewController isWalk:self.legs[section]]) return nil;
    NSInteger prev = section - 1;
    while (prev >= 0 && [JourneyDetailViewController isWalk:self.legs[prev]]) prev--;
    if (prev < 0) return nil;
    NSDate *a = [JourneyDetailViewController arr:self.legs[prev]];
    NSDate *d = [JourneyDetailViewController dep:self.legs[section]];
    if (!a || !d) return nil;
    return [NSString stringWithFormat:@"Umstieg · %ld min Zeit", (long)round([d timeIntervalSinceDate:a] / 60.0)];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [JourneyDetailViewController isWalk:self.legs[section]] ? 1 : 3;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([JourneyDetailViewController isWalk:self.legs[indexPath.section]]) return 48;
    return indexPath.row == 0 ? 56 : 52;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CardCell *cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSDictionary *leg = self.legs[indexPath.section];

    if ([JourneyDetailViewController isWalk:leg]) {
        NSDate *d = [JourneyDetailViewController dep:leg], *a = [JourneyDetailViewController arr:leg];
        NSInteger mins = (d && a) ? MAX(1, (NSInteger)round([a timeIntervalSinceDate:d] / 60.0)) : 1;
        NSNumber *dist = NN(leg[@"distance"]);
        cell.textLabel.text = [NSString stringWithFormat:@"🚶  %ld min zu Fuß%@", (long)mins,
                               dist ? [NSString stringWithFormat:@" · %@ m", dist] : @""];
        cell.textLabel.font = [BVGTheme font:14 weight:UIFontWeightMedium];
        cell.textLabel.textColor = [BVGTheme textSecondary];
        cell.cardColor = [BVGTheme background];
        return cell;
    }

    if (indexPath.row == 0) {
        cell.imageView.image = [BVGAPI badgeForLine:leg[@"line"]];
        cell.textLabel.text = [@"→ " stringByAppendingString:[BVGAPI shortName:NN(leg[@"direction"])] ?: @""];
        cell.textLabel.font = [BVGTheme font:15 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = [NN(leg[@"cancelled"]) boolValue] ? @"Fällt aus" : @"Fahrtverlauf ansehen";
        cell.detailTextLabel.textColor = [NN(leg[@"cancelled"]) boolValue] ? [BVGTheme red] : [BVGTheme link];
        cell.detailTextLabel.font = [BVGTheme font:13 weight:UIFontWeightMedium];
        if (NN(leg[@"tripId"])) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        return cell;
    }

    BOOL isDep = indexPath.row == 1;
    NSDictionary *place = NN(leg[isDep ? @"origin" : @"destination"]);
    NSDate *t = isDep ? [JourneyDetailViewController dep:leg] : [JourneyDetailViewController arr:leg];
    NSInteger delay = [NN(leg[isDep ? @"departureDelay" : @"arrivalDelay"]) integerValue] / 60;
    NSString *platform = [BVGAPI platform:NN(leg[isDep ? @"departurePlatform" : @"arrivalPlatform"])];

    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:[BVGAPI hhmm:t]
        attributes:@{ NSFontAttributeName: [BVGTheme digits:15 weight:UIFontWeightSemibold],
                      NSForegroundColorAttributeName: delay > 0 ? [BVGTheme red] : [BVGTheme textPrimary] }];
    [title appendAttributedString:[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:[BVGAPI shortName:NN(place[@"name"])] ?: @"?"]
        attributes:@{ NSFontAttributeName: [BVGTheme font:15 weight:UIFontWeightRegular],
                      NSForegroundColorAttributeName: [BVGTheme textPrimary] }]];
    cell.textLabel.attributedText = title;

    NSMutableArray *sub = [NSMutableArray arrayWithObject:isDep ? @"Einsteigen" : @"Aussteigen"];
    if (platform) [sub addObject:[NSString stringWithFormat:@"Gleis %@", platform]];
    if (delay > 0) [sub addObject:[NSString stringWithFormat:@"+%ld min", (long)delay]];
    cell.detailTextLabel.text = [sub componentsJoinedByString:@"  ·  "];
    cell.detailTextLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
    cell.imageView.image = [BVGAPI dotWithColor:[BVGAPI colorForLine:leg[@"line"]] filled:isDep];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *leg = self.legs[indexPath.section];
    if ([JourneyDetailViewController isWalk:leg] || indexPath.row != 0 || !NN(leg[@"tripId"])) return;

    TripViewController *trip = [[TripViewController alloc] initWithTripId:leg[@"tripId"]];
    trip.line = leg[@"line"];
    trip.stopName = NN(NN(leg[@"origin"])[@"name"]);
    [self.navigationController pushViewController:trip animated:YES];
}

@end
