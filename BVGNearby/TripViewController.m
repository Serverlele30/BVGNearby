#import "TripViewController.h"
#import "TripMapViewController.h"
#import "BVGAPI.h"

#pragma mark - Timeline-Zelle

@interface TimelineView : UIView
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) BOOL topLine, bottomLine, past, current;
@end

@implementation TimelineView
- (void)drawRect:(CGRect)rect {
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    UIColor *passed = [BVGTheme textTertiary];
    // Linie oben (zum vorherigen Halt) und unten (zum naechsten)
    if (self.topLine) {
        [(self.past || self.current ? passed : self.color) setFill];
        UIRectFill(CGRectMake(cx - 2, 0, 4, cy));
    }
    if (self.bottomLine) {
        [(self.past ? passed : self.color) setFill];
        UIRectFill(CGRectMake(cx - 2, cy, 4, self.bounds.size.height - cy));
    }
    CGFloat r = self.current ? 8 : 6;
    UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - r, cy - r, 2 * r, 2 * r)];
    if (self.current) {
        [self.color setFill]; [dot fill];
        UIBezierPath *inner = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 3, cy - 3, 6, 6)];
        [[UIColor whiteColor] setFill]; [inner fill];
    } else {
        [[UIColor whiteColor] setFill]; [dot fill];
        dot.lineWidth = 3;
        [(self.past ? passed : self.color) setStroke]; [dot stroke];
    }
}
@end

@interface TimelineCell : CardCell
@property (nonatomic, strong) TimelineView *timeline;
@property (nonatomic, strong) UILabel *nameLabel, *timeLabel, *noteLabel;
@end

@implementation TimelineCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _timeline = [[TimelineView alloc] init];
        _timeline.backgroundColor = [UIColor clearColor];
        _timeline.contentMode = UIViewContentModeRedraw;
        [self.contentView addSubview:_timeline];
        _nameLabel = [[UILabel alloc] init];
        [self.contentView addSubview:_nameLabel];
        _noteLabel = [[UILabel alloc] init];
        _noteLabel.font = [BVGTheme font:12 weight:UIFontWeightMedium];
        [self.contentView addSubview:_noteLabel];
        _timeLabel = [[UILabel alloc] init];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        _timeLabel.font = [BVGTheme digits:14 weight:UIFontWeightMedium];
        [self.contentView addSubview:_timeLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
    self.timeline.frame = CGRectMake(12, 0, 28, h);
    BOOL note = self.noteLabel.text.length > 0;
    self.nameLabel.frame = CGRectMake(50, note ? 7 : 0, w - 50 - 92, note ? 20 : h);
    self.noteLabel.frame = CGRectMake(50, 27, w - 50 - 92, 15);
    self.timeLabel.frame = CGRectMake(w - 92, 0, 80, h);
}
@end

#pragma mark - Controller

@interface TripViewController ()
@property (nonatomic, copy) NSString *tripId;
@property (nonatomic, copy) NSString *direction;
@property (nonatomic, strong) NSArray *stopovers;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, assign) BOOL didScroll;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation TripViewController

- (instancetype)initWithTripId:(NSString *)tripId {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _tripId = [tripId copy];
        _stopovers = @[];
        _currentIndex = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = NN(self.line[@"name"]) ?: @"Fahrt";
    self.tableView.rowHeight = 50;
    [self buildHeaderWithDirection:nil];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Karte"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(openMap)];
    [self load];
}

// Kopf: grosses Linien-Badge + Richtung
- (void)buildHeaderWithDirection:(NSString *)direction {
    CGFloat w = self.tableView.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width;
    CGFloat x = [BVGTheme cardInset] + 4;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 86)];

    UIImageView *badge = [[UIImageView alloc] initWithImage:[BVGAPI badgeForLine:self.line]];
    badge.frame = CGRectMake(x, 10, badge.image.size.width, badge.image.size.height);
    [header addSubview:badge];

    UILabel *dir = [[UILabel alloc] initWithFrame:CGRectMake(x, 40, w - 2 * x, 34)];
    dir.font = [BVGTheme font:22 weight:UIFontWeightBold];
    dir.textColor = [BVGTheme textPrimary];
    dir.adjustsFontSizeToFitWidth = YES;
    dir.minimumScaleFactor = 0.6;
    dir.text = direction ? [@"→ " stringByAppendingString:direction] : @"Lade Fahrtverlauf …";
    dir.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:dir];
    self.tableView.tableHeaderView = header;
}

- (void)openMap {
    TripMapViewController *map = [[TripMapViewController alloc] initWithTripId:self.tripId line:self.line];
    [self.navigationController pushViewController:map animated:YES];
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

- (void)load {
    NSString *path = [NSString stringWithFormat:@"/trips/%@?stopovers=true&remarks=false&polyline=false", [BVGAPI encode:self.tripId]];
    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        NSDictionary *trip = [json isKindOfClass:[NSDictionary class]] ? NN(json[@"trip"]) : nil;
        id rawStops = NN(trip[@"stopovers"]);
        NSArray *stops = [rawStops isKindOfClass:[NSArray class]] ? rawStops : @[];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.refreshControl endRefreshing];
            if (!trip) {
                NSLog(@"Trip-Fehler: %@", error);
                if (!self.stopovers.count) [self showEmptyIcon:@"📡" title:@"Nicht verfügbar" text:@"Der Fahrtverlauf konnte nicht geladen werden."];
                return;
            }
            [self showEmptyIcon:nil title:nil text:nil];
            NSString *dir = NN(trip[@"direction"]);
            if (!(dir == self.direction || [dir isEqualToString:self.direction])) {
                self.direction = dir;
                [self buildHeaderWithDirection:dir];
            }
            self.stopovers = stops;
            self.currentIndex = [self findCurrentIndex];
            [self.tableView reloadData];

            if (!self.didScroll && self.currentIndex >= 0 && self.currentIndex < (NSInteger)stops.count) {
                self.didScroll = YES;
                [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.currentIndex inSection:0]
                                      atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
            }
        });
    }];
}

- (NSDate *)timeOf:(NSDictionary *)so {
    return [BVGAPI dateFromISO:so[@"departure"]] ?: [BVGAPI dateFromISO:so[@"arrival"]]
        ?: [BVGAPI dateFromISO:so[@"plannedDeparture"]] ?: [BVGAPI dateFromISO:so[@"plannedArrival"]];
}

- (NSInteger)findCurrentIndex {
    NSDate *now = [NSDate date];
    for (NSInteger i = 0; i < (NSInteger)self.stopovers.count; i++) {
        NSDate *t = [self timeOf:self.stopovers[i]];
        if (t && [t compare:now] != NSOrderedAscending) return i;
    }
    return (NSInteger)self.stopovers.count - 1;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.stopovers.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *so = self.stopovers[indexPath.row];
    NSString *name = NN(NN(so[@"stop"])[@"name"]);
    BOOL mine = self.stopName && [name isEqualToString:self.stopName];
    return (indexPath.row == self.currentIndex || mine || [NN(so[@"cancelled"]) boolValue]) ? 52 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TimelineCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stop"];
    if (!cell) cell = [[TimelineCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"stop"];

    NSDictionary *so = self.stopovers[indexPath.row];
    NSString *name = NN(NN(so[@"stop"])[@"name"]) ?: @"?";
    BOOL past      = indexPath.row < self.currentIndex;
    BOOL current   = indexPath.row == self.currentIndex;
    BOOL mine      = self.stopName && [name isEqualToString:self.stopName];
    BOOL cancelled = [NN(so[@"cancelled"]) boolValue];

    cell.timeline.color = [BVGAPI colorForLine:self.line];
    cell.timeline.topLine = indexPath.row > 0;
    cell.timeline.bottomLine = indexPath.row < (NSInteger)self.stopovers.count - 1;
    cell.timeline.past = past;
    cell.timeline.current = current;
    [cell.timeline setNeedsDisplay];

    cell.nameLabel.text = name;
    cell.nameLabel.font = (current || mine) ? [BVGTheme font:15 weight:UIFontWeightSemibold] : [BVGTheme font:15 weight:UIFontWeightRegular];
    cell.nameLabel.textColor = past ? [BVGTheme textTertiary] : [BVGTheme textPrimary];

    if (cancelled)    { cell.noteLabel.text = @"Halt entfällt"; cell.noteLabel.textColor = [BVGTheme red]; }
    else if (current) { cell.noteLabel.text = @"Nächster Halt"; cell.noteLabel.textColor = [BVGTheme green]; }
    else if (mine)    { cell.noteLabel.text = @"Deine Haltestelle"; cell.noteLabel.textColor = [BVGTheme link]; }
    else              { cell.noteLabel.text = nil; }

    NSDate *t = [self timeOf:so];
    NSInteger delay = [(NN(so[@"departureDelay"]) ?: NN(so[@"arrivalDelay"])) integerValue] / 60;
    NSMutableAttributedString *time = [[NSMutableAttributedString alloc] initWithString:[BVGAPI hhmm:t] attributes:@{
        NSForegroundColorAttributeName: past ? [BVGTheme textTertiary] : [BVGTheme textPrimary] }];
    if (delay > 0) {
        [time appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" +%ld", (long)delay]
            attributes:@{ NSForegroundColorAttributeName: [BVGTheme red] }]];
    }
    cell.timeLabel.attributedText = time;
    cell.cardColor = current ? [BVGTheme accentSoft] : nil;
    [cell setNeedsLayout];
    return cell;
}

@end
