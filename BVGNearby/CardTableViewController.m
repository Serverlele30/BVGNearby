#import "CardTableViewController.h"

@interface CardTableViewController ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation CardTableViewController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    return [super initWithStyle:UITableViewStyleGrouped];   // nicht klebende Abschnittstitel
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [BVGTheme background];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.sectionHeaderHeight = 0;
    self.tableView.sectionFooterHeight = 0;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 16, 0);
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 8)];
    if (self.largeTitle) [self updateLargeHeader];
    else self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 6)];   // sonst 35 pt Luft (grouped)
}

#pragma mark - Grosser Titel

- (void)setLargeTitle:(NSString *)largeTitle {
    _largeTitle = [largeTitle copy];
    if (self.isViewLoaded) [self updateLargeHeader];
}

- (void)setLargeSubtitle:(NSString *)largeSubtitle {
    BOOL changed = !(largeSubtitle == _largeSubtitle || [largeSubtitle isEqualToString:_largeSubtitle]);
    _largeSubtitle = [largeSubtitle copy];
    if (!self.isViewLoaded || !changed) return;
    // nur Text tauschen, wenn sich die Hoehe nicht aendert (kein Springen)
    if (self.subtitleLabel && largeSubtitle.length) {
        self.subtitleLabel.text = largeSubtitle;
        self.subtitleLabel.textColor = self.largeSubtitleColor ?: [BVGTheme textSecondary];
    } else {
        [self updateLargeHeader];
    }
}

- (void)setLargeSubtitleColor:(UIColor *)largeSubtitleColor {
    _largeSubtitleColor = largeSubtitleColor;
    self.subtitleLabel.textColor = largeSubtitleColor ?: [BVGTheme textSecondary];
}

- (void)setHeaderAccessory:(UIView *)headerAccessory {
    _headerAccessory = headerAccessory;
    if (self.isViewLoaded) [self updateLargeHeader];
}

- (void)updateLargeHeader {
    CGFloat w = self.tableView.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width;
    CGFloat x = [BVGTheme cardInset] + 4;
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    CGFloat y = 2;

    if (self.largeTitle) {
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w - 2 * x, 40)];
        self.titleLabel.font = [BVGTheme font:32 weight:UIFontWeightBold];
        self.titleLabel.textColor = [BVGTheme textPrimary];
        self.titleLabel.text = self.largeTitle;
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.7;
        self.titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addSubview:self.titleLabel];
        y += 40;
    }
    if (self.largeSubtitle.length) {
        self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w - 2 * x, 18)];
        self.subtitleLabel.font = [BVGTheme font:14 weight:UIFontWeightMedium];
        self.subtitleLabel.textColor = self.largeSubtitleColor ?: [BVGTheme textSecondary];
        self.subtitleLabel.text = self.largeSubtitle;
        self.subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addSubview:self.subtitleLabel];
        y += 20;
    } else {
        self.subtitleLabel = nil;
    }
    if (self.headerAccessory) {
        y += 8;
        CGRect f = self.headerAccessory.frame;
        f.origin = CGPointMake(0, y);
        f.size.width = w;
        self.headerAccessory.frame = f;
        self.headerAccessory.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addSubview:self.headerAccessory];
        y += f.size.height;
    }
    header.frame = CGRectMake(0, 0, w, y + 4);
    self.tableView.tableHeaderView = header;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!self.largeTitle) return;
    BOOL scrolledAway = scrollView.contentOffset.y + scrollView.contentInset.top > 36;
    NSString *wanted = scrolledAway ? self.largeTitle : nil;
    if (!(wanted == self.navigationItem.title || [wanted isEqualToString:self.navigationItem.title])) {
        self.navigationItem.title = wanted;
    }
}

#pragma mark - Leerer Zustand

- (void)showEmptyIcon:(NSString *)icon title:(NSString *)title text:(NSString *)text {
    if (!icon && !title && !text) { self.tableView.backgroundView = nil; return; }

    UIView *v = [[UIView alloc] initWithFrame:self.tableView.bounds];
    UILabel *l = [[UILabel alloc] init];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    ps.paragraphSpacing = 6;
    if (icon)  [s appendAttributedString:[[NSAttributedString alloc] initWithString:[icon stringByAppendingString:@"\n"]
        attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:46], NSParagraphStyleAttributeName: ps }]];
    if (title) [s appendAttributedString:[[NSAttributedString alloc] initWithString:[title stringByAppendingString:@"\n"]
        attributes:@{ NSFontAttributeName: [BVGTheme font:19 weight:UIFontWeightSemibold],
                      NSForegroundColorAttributeName: [BVGTheme textPrimary], NSParagraphStyleAttributeName: ps }]];
    if (text)  [s appendAttributedString:[[NSAttributedString alloc] initWithString:text
        attributes:@{ NSFontAttributeName: [BVGTheme font:15 weight:UIFontWeightRegular],
                      NSForegroundColorAttributeName: [BVGTheme textSecondary], NSParagraphStyleAttributeName: ps }]];
    l.attributedText = s;
    CGFloat w = v.bounds.size.width - 64;
    CGSize size = [l sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
    l.frame = CGRectMake(32, MAX(60, v.bounds.size.height * 0.38 - size.height / 2), w, size.height);
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:l];
    self.tableView.backgroundView = v;
}

#pragma mark - Abschnittstitel & -fuss

+ (UILabel *)sectionLabelWithText:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [BVGTheme font:15 weight:UIFontWeightSemibold];
    l.textColor = [BVGTheme textSecondary];
    return l;
}

- (NSString *)headerTitleFor:(NSInteger)section {
    if (![self respondsToSelector:@selector(tableView:titleForHeaderInSection:)]) return nil;
    return [(id<UITableViewDataSource>)self tableView:self.tableView titleForHeaderInSection:section];
}

- (NSString *)footerTitleFor:(NSInteger)section {
    if (![self respondsToSelector:@selector(tableView:titleForFooterInSection:)]) return nil;
    return [(id<UITableViewDataSource>)self tableView:self.tableView titleForFooterInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self headerTitleFor:section].length) return 42;
    return section == 0 ? 8 : 20;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self headerTitleFor:section];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, title.length ? 42 : 8)];
    if (!title.length) return v;
    UILabel *l = [CardTableViewController sectionLabelWithText:title];
    l.frame = CGRectMake([BVGTheme cardInset] + 4, 16, v.bounds.size.width - 2 * [BVGTheme cardInset] - 8, 20);
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:l];
    return v;
}

- (CGFloat)footerTextHeight:(NSString *)text {
    CGFloat w = self.tableView.bounds.size.width - 2 * ([BVGTheme cardInset] + 4);
    CGRect r = [text boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{ NSFontAttributeName: [BVGTheme font:13 weight:UIFontWeightRegular] }
                                  context:nil];
    return ceil(r.size.height);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self footerTitleFor:section];
    return text.length ? [self footerTextHeight:text] + 16 : 0.01;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self footerTitleFor:section];
    if (!text.length) return [[UIView alloc] initWithFrame:CGRectZero];
    CGFloat h = [self footerTextHeight:text];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, h + 16)];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake([BVGTheme cardInset] + 4, 8,
                                                           v.bounds.size.width - 2 * ([BVGTheme cardInset] + 4), h)];
    l.numberOfLines = 0;
    l.font = [BVGTheme font:13 weight:UIFontWeightRegular];
    l.textColor = [BVGTheme textSecondary];
    l.text = text;
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:l];
    return v;
}

#pragma mark - Kartenposition

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:[CardCell class]]) return;
    CardCell *c = (CardCell *)cell;
    NSInteger rows = [self tableView:tableView numberOfRowsInSection:indexPath.section];
    c.firstInSection = indexPath.row == 0;
    c.lastInSection = indexPath.row == rows - 1;
    [c applyCardStyle];
}

@end
