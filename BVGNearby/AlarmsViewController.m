#import "AlarmsViewController.h"
#import "BVGAPI.h"

@interface AlarmsViewController ()
@property (nonatomic, strong) NSArray *alarms;
@end

@implementation AlarmsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.largeTitle = @"Wecker";
    self.tableView.rowHeight = 72;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload)
                                                 name:BVGAlarmsChangedNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    self.alarms = [[BVGAPI userAlarms] sortedArrayUsingComparator:^NSComparisonResult(UILocalNotification *a, UILocalNotification *b) {
        return [a.fireDate compare:b.fireDate];
    }];
    if (self.alarms.count == 0) {
        self.largeSubtitle = nil;
        [self showEmptyIcon:@"⏰" title:@"Keine Wecker"
                       text:@"Wische bei einer Abfahrt nach links und tippe auf „Wecker“. Bei Stummschalter wird nur vibriert."];
    } else {
        self.largeSubtitle = self.alarms.count == 1 ? @"1 Erinnerung aktiv"
                                                    : [NSString stringWithFormat:@"%lu Erinnerungen aktiv", (unsigned long)self.alarms.count];
        [self showEmptyIcon:nil title:nil text:nil];
    }
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.alarms.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.alarms.count ? @"Zum Löschen nach links wischen." : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"alarm"];
    if (!cell) cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"alarm"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UILocalNotification *n = self.alarms[indexPath.row];
    NSString *line = n.userInfo[@"line"];
    NSString *dir  = n.userInfo[@"direction"];
    NSString *stop = n.userInfo[@"stop"];
    NSDate *dep    = n.userInfo[@"departure"];

    // grosse Weckzeit links, darunter die Fahrt
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:[BVGAPI hhmm:n.fireDate]
        attributes:@{ NSFontAttributeName: [BVGTheme digits:22 weight:UIFontWeightSemibold],
                      NSForegroundColorAttributeName: [BVGTheme textPrimary] }];
    NSInteger mins = (NSInteger)floor([n.fireDate timeIntervalSinceNow] / 60.0);
    NSString *rest = mins >= 60 ? [NSString stringWithFormat:@"  in %ld:%02ld h", (long)(mins / 60), (long)(mins % 60)]
                                : [NSString stringWithFormat:@"  in %ld min", (long)MAX(mins, 0)];
    [title appendAttributedString:[[NSAttributedString alloc] initWithString:rest
        attributes:@{ NSFontAttributeName: [BVGTheme font:14 weight:UIFontWeightMedium],
                      NSForegroundColorAttributeName: [BVGTheme warningText] }]];
    cell.textLabel.attributedText = title;

    NSMutableString *sub = [NSMutableString string];
    if (line) [sub appendFormat:@"%@ → %@", line, dir ?: @""];
    else [sub appendString:n.alertBody ?: @""];
    if ([dep isKindOfClass:[NSDate class]]) [sub appendFormat:@"  ·  ab %@", [BVGAPI hhmm:dep]];
    if (stop.length) [sub appendFormat:@" %@", stop];
    cell.detailTextLabel.text = sub;
    cell.detailTextLabel.font = [BVGTheme font:14 weight:UIFontWeightRegular];
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                            forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    [[UIApplication sharedApplication] cancelLocalNotification:self.alarms[indexPath.row]];
    [[NSNotificationCenter defaultCenter] postNotificationName:BVGAlarmsChangedNotification object:nil];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Löschen";
}

@end
