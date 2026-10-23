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
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 48;

    UIBarButtonItem *check = [[UIBarButtonItem alloc] initWithTitle:@"Prüfen" style:UIBarButtonItemStylePlain
                                                             target:self action:@selector(check)];
    UIBarButtonItem *speak = [[UIBarButtonItem alloc] initWithTitle:@"Ansage" style:UIBarButtonItemStylePlain
                                                             target:self action:@selector(speak)];
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CardCell *cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    GuidanceManager *g = [GuidanceManager shared];
    NSArray *legs = [self legs];

    switch ([self kind:indexPath.section]) {
        case GSectionStatus: {
            if (indexPath.row == 0) {
                cell.textLabel.text = [g currentInstruction];
                cell.textLabel.font = [BVGTheme font:20 weight:UIFontWeightSemibold];
                cell.cardColor = [BVGTheme accent];
            } else if (indexPath.row == 1) {
                switch (g.status) {
                    case GuidanceStatusOK:
                        cell.textLabel.text = @"✓ Alle Anschlüsse erreichbar";
                        cell.textLabel.textColor = [BVGTheme green];
                        break;
                    case GuidanceStatusAtRisk:
                        cell.textLabel.text = [@"⚠ " stringByAppendingString:g.problemText ?: @"Umstieg knapp"];
                        cell.textLabel.textColor = [BVGTheme orange];
                        break;
                    case GuidanceStatusBroken:
                        cell.textLabel.text = [@"✕ " stringByAppendingString:g.problemText ?: @"Route nicht mehr möglich"];
                        cell.textLabel.textColor = [BVGTheme red];
                        break;
                    case GuidanceStatusDone:
                        cell.textLabel.text = @"🎉 Ziel erreicht";
                        break;
                }
                cell.textLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
            } else {
                NSDictionary *last = legs.lastObject;
                NSDate *arr = [GuidanceManager legArrival:last];
                NSInteger delay = [NN(last[@"arrivalDelay"]) integerValue] / 60;
                cell.textLabel.text = [NSString stringWithFormat:@"Ankunft %@%@", [BVGAPI hhmm:arr],
                                       delay > 0 ? [NSString stringWithFormat:@" (+%ld)", (long)delay] : @""];
                cell.detailTextLabel.text = NN(NN(last[@"destination"])[@"name"]);
                cell.textLabel.font = [BVGTheme digits:17 weight:UIFontWeightMedium];
            }
            return cell;
        }

        case GSectionAlternative: {
            NSArray *alt = [self altLegs];
            if (indexPath.row == 0) {
                NSMutableArray *lines = [NSMutableArray array];
                for (NSDictionary *l in alt) if (![GuidanceManager isWalk:l]) [lines addObject:l[@"line"]];
                cell.imageView.image = [BVGAPI badgeStripForLines:lines];
                NSDate *dep = [GuidanceManager legDeparture:alt.firstObject];
                NSDate *arr = [GuidanceManager legArrival:alt.lastObject];
                NSDate *oldArr = [GuidanceManager legArrival:legs.lastObject];
                NSInteger diff = (arr && oldArr) ? (NSInteger)round([arr timeIntervalSinceDate:oldArr] / 60.0) : 0;
                cell.textLabel.text = [NSString stringWithFormat:@"%@ → %@", [BVGAPI hhmm:dep], [BVGAPI hhmm:arr]];
                cell.textLabel.font = [BVGTheme digits:17 weight:UIFontWeightSemibold];
                cell.detailTextLabel.text = diff > 0 ? [NSString stringWithFormat:@"%ld min später als geplant", (long)diff]
                                                     : @"Ankunft wie geplant oder früher";
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"✓ Alternative übernehmen";
                cell.textLabel.textColor = [BVGTheme green];
                cell.textLabel.font = [BVGTheme font:17 weight:UIFontWeightSemibold];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            } else {
                cell.textLabel.text = @"Aktuelle Route behalten";
                cell.textLabel.textColor = [BVGTheme textSecondary];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
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
            NSString *origin = NN(NN(leg[@"origin"])[@"name"]) ?: @"";
            NSString *dest = NN(NN(leg[@"destination"])[@"name"]) ?: @"";

            if ([GuidanceManager isWalk:leg]) {
                NSInteger mins = (dep && arr) ? (NSInteger)round([arr timeIntervalSinceDate:dep] / 60.0) : 0;
                cell.textLabel.text = [NSString stringWithFormat:@"🚶 %ld min zu Fuß", (long)mins];
                cell.detailTextLabel.text = [@"bis " stringByAppendingString:dest];
            } else {
                cell.imageView.image = [BVGAPI badgeForLine:leg[@"line"]];
                NSInteger dd = [NN(leg[@"departureDelay"]) integerValue] / 60;
                cell.textLabel.text = [NSString stringWithFormat:@"%@%@ %@ → %@", [BVGAPI hhmm:dep],
                                       dd > 0 ? [NSString stringWithFormat:@" (+%ld)", (long)dd] : @"",
                                       origin, NN(leg[@"direction"]) ?: @""];
                NSString *dp = NN(leg[@"departurePlatform"]), *ap = NN(leg[@"arrivalPlatform"]);
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@ aussteigen: %@ um %@%@",
                                             dp ? [NSString stringWithFormat:@"Gl. %@ · ", dp] : @"",
                                             [NN(leg[@"cancelled"]) boolValue] ? @"FÄLLT AUS · " : @"",
                                             dest, [BVGAPI hhmm:arr], ap ? [NSString stringWithFormat:@" (Gl. %@)", ap] : @""];
                cell.accessoryType = NN(leg[@"tripId"]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            }
            cell.textLabel.font = indexPath.row == current ? [BVGTheme font:15 weight:UIFontWeightSemibold] : [BVGTheme font:15 weight:UIFontWeightRegular];
            cell.textLabel.textColor = done ? [BVGTheme textTertiary] : [BVGTheme textPrimary];
            cell.detailTextLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
            cell.detailTextLabel.textColor = [NN(leg[@"cancelled"]) boolValue] ? [BVGTheme red] : [BVGTheme textSecondary];
            if (indexPath.row == current) cell.cardColor = [BVGTheme accentSoft];
            return cell;
        }

        case GSectionEnd: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Ankunftszeit teilen";
                cell.textLabel.textColor = [BVGTheme link];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                return cell;
            }
            cell.textLabel.text = @"Navigation beenden";
            cell.textLabel.textColor = [BVGTheme red];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
    }
    return cell;
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
