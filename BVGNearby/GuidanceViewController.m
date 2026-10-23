#import "GuidanceViewController.h"
#import "GuidanceManager.h"
#import "TripViewController.h"
#import "BVGAPI.h"

typedef NS_ENUM(NSInteger, GSection) { GSectionStatus, GSectionAlternative, GSectionSteps, GSectionEnd };

@interface GuidanceViewController ()
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation GuidanceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Navigation";
    UIBarButtonItem *check = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                           target:self action:@selector(check)];
    UIBarButtonItem *speak = [BVGAPI barButtonWithIcon:@"speaker" target:self action:@selector(speak)];
    speak.accessibilityLabel = @"Anweisung ansagen";
    self.navigationItem.rightBarButtonItems = @[check, speak];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload)
                                                 name:GuidanceChangedNotification object:nil];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(reload) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)check {
    [[GuidanceManager shared] checkNow];
}

- (void)speak {
    if ([BVGAPI isSpeaking]) { [BVGAPI stopSpeaking]; return; }
    GuidanceManager *g = [GuidanceManager shared];
    NSMutableString *s = [NSMutableString stringWithString:[g currentInstruction]];
    if (g.problemText) [s appendFormat:@" Achtung: %@", g.problemText];
    if (g.alternative) [s appendString:@" Es gibt eine Alternative."];
    [BVGAPI speak:s];
}

// "Bin um 14:32 an der Seestraße (U8, S41)" per SMS/iMessage/Mail
- (void)shareArrival {
    NSArray *legs = [self legs];
    NSDictionary *last = legs.lastObject;
    NSDate *arr = [GuidanceManager legArrival:last];
    NSString *dest = NN(NN(last[@"destination"])[@"name"]) ?: @"am Ziel";
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *l in legs) if (![GuidanceManager isWalk:l]) [lines addObject:NN(NN(l[@"line"])[@"name"]) ?: @"?"];
    NSInteger delay = [NN(last[@"arrivalDelay"]) integerValue] / 60;

    NSMutableString *text = [NSMutableString stringWithFormat:@"Bin voraussichtlich um %@ Uhr an %@", [BVGAPI hhmm:arr], dest];
    if (lines.count) [text appendFormat:@" (mit %@)", [lines componentsJoinedByString:@" → "]];
    if (delay > 0) [text appendFormat:@", aktuell %ld min später als geplant", (long)delay];
    [text appendString:@"."];

    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    [self presentViewController:share animated:YES completion:nil];
}

- (void)reload {
    GuidanceManager *g = [GuidanceManager shared];
    if (!g.active) {
        self.sections = @[];
        [self showEmptyIcon:@"🧭" title:@"Keine Navigation"
                       text:@"Plane eine Route und tippe in der Verbindung auf „Navigation starten“."];
    } else {
        [self showEmptyIcon:nil title:nil text:nil];
        NSMutableArray *s = [NSMutableArray arrayWithObject:@(GSectionStatus)];
        if (g.alternative) [s addObject:@(GSectionAlternative)];
        [s addObject:@(GSectionSteps)];
        [s addObject:@(GSectionEnd)];
        self.sections = s;
    }
    [self.tableView reloadData];
}

- (NSArray *)legs {
    id legs = NN([GuidanceManager shared].journey[@"legs"]);
    return [legs isKindOfClass:[NSArray class]] ? legs : @[];
}

- (NSArray *)altLegs {
    id legs = NN([GuidanceManager shared].alternative[@"legs"]);
    return [legs isKindOfClass:[NSArray class]] ? legs : @[];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (GSection)kind:(NSInteger)section {
    return (GSection)[self.sections[section] integerValue];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ([self kind:section]) {
        case GSectionAlternative: return @"Alternative – du entscheidest";
        case GSectionSteps:       return @"Deine Route";
        default:                  return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self kind:section] != GSectionStatus) return nil;
    GuidanceManager *g = [GuidanceManager shared];
    if (g.checking) return @"Prüfe Echtzeitdaten…";
    return [NSString stringWithFormat:@"Geprüft %@ · automatisch jede Minute. Erinnerungen kommen auch bei gesperrtem Gerät.",
            [BVGAPI hhmm:g.lastCheck]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self kind:section]) {
        case GSectionStatus:      return 3;
        case GSectionAlternative: return 3;
        case GSectionSteps:       return [self legs].count;
        case GSectionEnd:         return 2;   // Teilen + Beenden
    }
    return 0;
}

+ (NSString *)name:(NSDictionary *)place {
    return [BVGAPI shortName:NN(NN(place)[@"name"])] ?: @"";
}

// "18:05 (+2)" bzw. "18:05"
+ (NSString *)time:(NSDate *)t delay:(id)delaySeconds {
    NSInteger d = [NN(delaySeconds) integerValue] / 60;
    return d > 0 ? [NSString stringWithFormat:@"%@ (+%ld)", [BVGAPI hhmm:t], (long)d] : [BVGAPI hhmm:t];
}

- (InfoCell *)cellAt:(NSIndexPath *)indexPath {
    InfoCell *cell = [[InfoCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    GuidanceManager *g = [GuidanceManager shared];
    NSArray *legs = [self legs];

    switch ([self kind:indexPath.section]) {
        case GSectionStatus: {
            if (indexPath.row == 0) {
                cell.titleLabel.text = [BVGAPI shortName:[g currentInstruction]];
                cell.titleLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
                cell.titleLabel.textColor = [UIColor whiteColor];
                cell.cardColor = [BVGTheme textPrimary];   // aktuelle Anweisung hervorgehoben
            } else if (indexPath.row == 1) {
                switch (g.status) {
                    case GuidanceStatusOK:
                        cell.titleLabel.text = @"✓ Alle Anschlüsse erreichbar";
                        cell.titleLabel.textColor = [BVGTheme green];
                        break;
                    case GuidanceStatusAtRisk:
                        cell.titleLabel.text = [@"⚠︎ " stringByAppendingString:g.problemText ?: @"Umstieg knapp"];
                        cell.titleLabel.textColor = [BVGTheme warningText];
                        break;
                    case GuidanceStatusBroken:
                        cell.titleLabel.text = [@"✕ " stringByAppendingString:g.problemText ?: @"Route nicht mehr möglich"];
                        cell.titleLabel.textColor = [BVGTheme red];
                        break;
                    case GuidanceStatusDone:
                        cell.titleLabel.text = @"Ziel erreicht";
                        break;
                }
                cell.titleLabel.font = [BVGTheme font:14 weight:UIFontWeightSemibold];
            } else {
                NSDictionary *last = legs.lastObject;
                cell.titleLabel.text = [NSString stringWithFormat:@"Ankunft %@",
                                        [GuidanceViewController time:[GuidanceManager legArrival:last] delay:last[@"arrivalDelay"]]];
                cell.titleLabel.font = [BVGTheme digits:14 weight:UIFontWeightSemibold];
                cell.detailLabel.text = [GuidanceViewController name:last[@"destination"]];
            }
            return cell;
        }

        case GSectionAlternative: {
            NSArray *alt = [self altLegs];
            if (indexPath.row == 0) {
                NSMutableArray *lines = [NSMutableArray array];
                for (NSDictionary *l in alt) if (![GuidanceManager isWalk:l]) [lines addObject:l[@"line"]];
                cell.iconView.image = [BVGAPI badgeStripForLines:lines];
                NSDate *dep = [GuidanceManager legDeparture:alt.firstObject];
                NSDate *arr = [GuidanceManager legArrival:alt.lastObject];
                NSDate *oldArr = [GuidanceManager legArrival:legs.lastObject];
                NSInteger diff = (arr && oldArr) ? (NSInteger)round([arr timeIntervalSinceDate:oldArr] / 60.0) : 0;
                cell.titleLabel.text = [NSString stringWithFormat:@"%@ – %@", [BVGAPI hhmm:dep], [BVGAPI hhmm:arr]];
                cell.titleLabel.font = [BVGTheme digits:15 weight:UIFontWeightSemibold];
                cell.detailLabel.text = diff > 0 ? [NSString stringWithFormat:@"%ld min später als geplant", (long)diff]
                                                 : @"Ankunft wie geplant oder früher";
            } else {
                BOOL accept = indexPath.row == 1;
                cell.titleLabel.text = accept ? @"Alternative übernehmen" : @"Aktuelle Route behalten";
                cell.titleLabel.textColor = accept ? [BVGTheme green] : [BVGTheme textSecondary];
                cell.titleLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            }
            return cell;
        }

        case GSectionSteps: {
            NSDictionary *leg = legs[indexPath.row];
            NSInteger current = [g currentLegIndex];
            BOOL done = indexPath.row < current;
            NSDate *dep = [GuidanceManager legDeparture:leg];
            NSDate *arr = [GuidanceManager legArrival:leg];
            NSString *origin = [GuidanceViewController name:leg[@"origin"]];
            NSString *dest = [GuidanceViewController name:leg[@"destination"]];

            if ([GuidanceManager isWalk:leg]) {
                NSInteger mins = (dep && arr) ? (NSInteger)round([arr timeIntervalSinceDate:dep] / 60.0) : 0;
                if (mins <= 1 && ([origin isEqualToString:dest] || !NN(leg[@"distance"]) || [NN(leg[@"distance"]) integerValue] < 80)) {
                    cell.titleLabel.text = @"Umsteigen";
                    cell.detailLabel.text = [@"am Bahnhof " stringByAppendingString:dest];
                } else {
                    cell.titleLabel.text = [NSString stringWithFormat:@"🚶 %ld min zu Fuß", (long)MAX(mins, 1)];
                    cell.detailLabel.text = [@"bis " stringByAppendingString:dest];
                }
                cell.titleLabel.font = [BVGTheme font:14 weight:UIFontWeightMedium];
            } else {
                cell.iconView.image = [BVGAPI badgeForLine:leg[@"line"]];
                cell.titleLabel.text = [@"→ " stringByAppendingString:[BVGAPI shortName:NN(leg[@"direction"])] ?: @""];
                cell.titleLabel.font = [BVGTheme font:15 weight:(indexPath.row == current ? UIFontWeightSemibold : UIFontWeightRegular)];

                NSString *dp = [BVGAPI platform:NN(leg[@"departurePlatform"])], *ap = [BVGAPI platform:NN(leg[@"arrivalPlatform"])];
                NSMutableString *d = [NSMutableString string];
                if ([NN(leg[@"cancelled"]) boolValue]) [d appendString:@"FÄLLT AUS\n"];
                [d appendFormat:@"ab %@  %@%@", [GuidanceViewController time:dep delay:leg[@"departureDelay"]], origin,
                                dp ? [NSString stringWithFormat:@" · Gl. %@", dp] : @""];
                [d appendFormat:@"\nan %@  %@%@", [GuidanceViewController time:arr delay:leg[@"arrivalDelay"]], dest,
                                ap ? [NSString stringWithFormat:@" · Gl. %@", ap] : @""];
                cell.detailLabel.text = d;
                cell.detailLabel.font = [BVGTheme digits:13 weight:UIFontWeightRegular];
                cell.accessoryType = NN(leg[@"tripId"]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            }
            cell.titleLabel.textColor = done ? [BVGTheme textTertiary] : [BVGTheme textPrimary];
            cell.detailLabel.textColor = [NN(leg[@"cancelled"]) boolValue] ? [BVGTheme red] : [BVGTheme textSecondary];
            if (indexPath.row == current) cell.cardColor = [BVGTheme accentSoft];
            if (done) cell.contentView.alpha = 0.5;
            return cell;
        }

        case GSectionEnd: {
            BOOL share = indexPath.row == 0;
            cell.titleLabel.text = share ? @"Ankunftszeit teilen" : @"Navigation beenden";
            cell.titleLabel.font = [BVGTheme font:15 weight:UIFontWeightRegular];
            cell.titleLabel.textColor = share ? [BVGTheme link] : [BVGTheme red];
            cell.titleLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [[self cellAt:indexPath] fittingHeightForTableWidth:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self cellAt:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    GuidanceManager *g = [GuidanceManager shared];

    switch ([self kind:indexPath.section]) {
        case GSectionAlternative:
            if (indexPath.row == 1) [g acceptAlternative];
            if (indexPath.row == 2) [g dismissAlternative];
            break;
        case GSectionSteps: {
            NSDictionary *leg = [self legs][indexPath.row];
            if ([GuidanceManager isWalk:leg] || !NN(leg[@"tripId"])) break;
            TripViewController *trip = [[TripViewController alloc] initWithTripId:leg[@"tripId"]];
            trip.line = leg[@"line"];
            trip.stopName = NN(NN(leg[@"destination"])[@"name"]);
            [self.navigationController pushViewController:trip animated:YES];
            break;
        }
        case GSectionEnd: {
            if (indexPath.row == 0) { [self shareArrival]; break; }
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Navigation beenden?" message:nil
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
            [a addAction:[UIAlertAction actionWithTitle:@"Beenden" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
                [[GuidanceManager shared] stop];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
            a.popoverPresentationController.sourceView = self.view;
            [self presentViewController:a animated:YES completion:nil];
            break;
        }
        default:
            break;
    }
}

@end
