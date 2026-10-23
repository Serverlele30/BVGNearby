#import "DepartureCell.h"
#import "BVGAPI.h"
#import "BVGTheme.h"

@interface DepartureCell ()
@property (nonatomic, strong) UIImageView *badgeView;
@property (nonatomic, strong) UILabel *directionLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UILabel *minutesLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation DepartureCell

+ (CGFloat)height { return 64; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _badgeView = [[UIImageView alloc] init];
        _badgeView.contentMode = UIViewContentModeLeft;
        [self.contentView addSubview:_badgeView];

        _directionLabel = [[UILabel alloc] init];
        _directionLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
        _directionLabel.textColor = [BVGTheme textPrimary];
        [self.contentView addSubview:_directionLabel];

        _infoLabel = [[UILabel alloc] init];
        _infoLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
        [self.contentView addSubview:_infoLabel];

        _minutesLabel = [[UILabel alloc] init];
        _minutesLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_minutesLabel];

        _subLabel = [[UILabel alloc] init];
        _subLabel.font = [BVGTheme digits:12 weight:UIFontWeightMedium];
        _subLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_subLabel];

        _emptyLabel = [[UILabel alloc] init];
        _emptyLabel.font = [BVGTheme font:15 weight:UIFontWeightRegular];
        _emptyLabel.textColor = [BVGTheme textSecondary];
        _emptyLabel.hidden = YES;
        [self.contentView addSubview:_emptyLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat right = 76;
    CGFloat textX = 80;

    self.badgeView.frame      = CGRectMake(14, (h - 24) / 2, 62, 24);
    self.directionLabel.frame = CGRectMake(textX, 12, w - textX - right - 6, 20);
    self.infoLabel.frame      = CGRectMake(textX, 34, w - textX - right - 6, 17);
    self.minutesLabel.frame   = CGRectMake(w - right - 14, 9, right, 28);
    self.subLabel.frame       = CGRectMake(w - right - 14, 37, right, 16);
    self.emptyLabel.frame     = CGRectMake(16, 0, w - 32, h);
}

- (void)setDimmed:(BOOL)dimmed {
    self.contentView.alpha = dimmed ? 0.38 : 1.0;
}

- (void)setAllHidden:(BOOL)hidden {
    for (UIView *v in @[self.badgeView, self.directionLabel, self.infoLabel, self.minutesLabel, self.subLabel]) v.hidden = hidden;
    self.emptyLabel.hidden = !hidden;
}

- (void)configureEmpty:(NSString *)text {
    [self setAllHidden:YES];
    self.contentView.alpha = 1.0;
    self.emptyLabel.text = text;
    self.accessibilityLabel = text;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)configureWithDeparture:(NSDictionary *)d {
    [self setAllHidden:NO];
    NSDictionary *line = NN(d[@"line"]);
    NSString *tripId   = NN(d[@"tripId"]);
    NSString *dir      = NN(d[@"direction"]) ?: @"";
    BOOL cancelled     = [NN(d[@"cancelled"]) boolValue];
    NSDate *when       = [BVGAPI whenOfDeparture:d];

    self.badgeView.image = [BVGAPI badgeForLine:line];
    self.selectionStyle  = tripId ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;

    // Richtung
    if (cancelled) {
        self.directionLabel.attributedText = [[NSAttributedString alloc] initWithString:dir attributes:@{
            NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle),
            NSFontAttributeName: [BVGTheme font:16 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: [BVGTheme textTertiary] }];
    } else {
        self.directionLabel.attributedText = nil;
        self.directionLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
        self.directionLabel.textColor = [BVGTheme textPrimary];
        self.directionLabel.text = dir;
    }

    // Infozeile: Wecker, Gleis/Gleiswechsel, Stoerung
    NSMutableArray *info = [NSMutableArray array];
    UIColor *infoColor = [BVGTheme textSecondary];
    if ([BVGAPI hasAlarmForTrip:tripId]) [info addObject:@"⏰ Wecker"];

    NSString *platform = NN(d[@"platform"]);
    NSString *planned  = NN(d[@"plannedPlatform"]);
    if (platform && planned && ![platform isEqualToString:planned]) {
        [info addObject:[NSString stringWithFormat:@"Gleis %@ statt %@", platform, planned]];
        infoColor = [BVGTheme orange];
    } else if (platform ?: planned) {
        [info addObject:[NSString stringWithFormat:@"Gleis %@", platform ?: planned]];
    }

    id remarks = NN(d[@"remarks"]);
    if ([remarks isKindOfClass:[NSArray class]]) {
        for (NSDictionary *r in remarks) {
            if ([r isKindOfClass:[NSDictionary class]] && [NN(r[@"type"]) isEqualToString:@"warning"]) {
                [info addObject:@"⚠︎ Störung"];
                infoColor = [BVGTheme orange];
                break;
            }
        }
    }
    if (cancelled) { [info insertObject:@"Fällt aus" atIndex:0]; infoColor = [BVGTheme red]; }
    if (!info.count && when) [info addObject:[NSString stringWithFormat:@"Abfahrt %@", [BVGAPI hhmm:when]]];
    self.infoLabel.text = [info componentsJoinedByString:@"  ·  "];
    self.infoLabel.textColor = infoColor;

    // rechte Spalte
    if (cancelled) {
        self.minutesLabel.attributedText = nil;
        self.minutesLabel.font = [BVGTheme font:15 weight:UIFontWeightSemibold];
        self.minutesLabel.textColor = [BVGTheme red];
        self.minutesLabel.text = @"Ausfall";
        self.subLabel.attributedText = [[NSAttributedString alloc] initWithString:[BVGAPI hhmm:when] attributes:@{
            NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle),
            NSForegroundColorAttributeName: [BVGTheme textTertiary] }];
        self.accessibilityLabel = [NSString stringWithFormat:@"%@ Richtung %@ fällt aus", [BVGAPI spokenLineName:line], dir];
        return;
    }

    NSInteger mins  = when ? (NSInteger)floor([when timeIntervalSinceNow] / 60.0) : -1;
    NSInteger delay = [NN(d[@"delay"]) integerValue] / 60;
    BOOL realtime   = NN(d[@"delay"]) != nil;
    UIColor *numberColor = delay > 0 ? [BVGTheme red] : [BVGTheme textPrimary];

    if (mins <= 0) {
        self.minutesLabel.attributedText = nil;
        self.minutesLabel.font = [BVGTheme font:18 weight:UIFontWeightBold];
        self.minutesLabel.textColor = delay > 0 ? [BVGTheme red] : [BVGTheme green];
        self.minutesLabel.text = @"jetzt";
    } else if (mins >= 60) {
        self.minutesLabel.attributedText = nil;
        self.minutesLabel.font = [BVGTheme digits:20 weight:UIFontWeightSemibold];
        self.minutesLabel.textColor = numberColor;
        self.minutesLabel.text = [BVGAPI hhmm:when];
    } else {
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%ld", (long)mins]
                attributes:@{ NSFontAttributeName: [BVGTheme digits:24 weight:UIFontWeightSemibold],
                              NSForegroundColorAttributeName: numberColor }];
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:@" min" attributes:@{
            NSFontAttributeName: [BVGTheme font:13 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: [BVGTheme textSecondary] }]];
        self.minutesLabel.attributedText = s;
    }

    self.subLabel.attributedText = nil;
    if (delay > 0) {
        self.subLabel.text = [NSString stringWithFormat:@"+%ld  %@", (long)delay, [BVGAPI hhmm:when]];
        self.subLabel.textColor = [BVGTheme red];
    } else {
        self.subLabel.text = [BVGAPI hhmm:when];
        self.subLabel.textColor = realtime ? [BVGTheme green] : [BVGTheme textSecondary];   // gruen = Echtzeit, puenktlich
    }

    // VoiceOver
    NSMutableString *ax = [NSMutableString stringWithFormat:@"%@ Richtung %@, ", [BVGAPI spokenLineName:line], dir];
    if (mins <= 0) [ax appendString:@"jetzt"];
    else [ax appendFormat:@"in %ld Minuten", (long)mins];
    if (delay > 0) [ax appendFormat:@", %ld Minuten verspätet", (long)delay];
    if (platform ?: planned) [ax appendFormat:@", Gleis %@", platform ?: planned];
    self.accessibilityLabel = ax;
    self.accessibilityHint = tripId ? @"Doppeltippen für den Fahrtverlauf" : nil;
}

@end
