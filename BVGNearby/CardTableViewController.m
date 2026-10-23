#import "CardTableViewController.h"

// Ruhiges Layout: Gelb nur in der Navigationsleiste, Inhalt auf hellgrauem Grund.
@interface CardTableViewController ()
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
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 12, 0);
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 8)];
    [self updateLargeHeader];
    // "Zurueck" statt "Back" (bzw. statt langer Titel wie "16:01 – 18:42")
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Zurück" style:UIBarButtonItemStylePlain
                                                                            target:nil action:nil];
}

#pragma mark - Titel & Kopf

- (void)setLargeTitle:(NSString *)largeTitle {
    _largeTitle = [largeTitle copy];
    self.navigationItem.title = largeTitle;   // Titel steht nur in der gelben Leiste
}

- (void)setLargeSubtitle:(NSString *)largeSubtitle {
    BOOL changed = !(largeSubtitle == _largeSubtitle || [largeSubtitle isEqualToString:_largeSubtitle]);
    _largeSubtitle = [largeSubtitle copy];
    if (!self.isViewLoaded || !changed) return;
    if (self.subtitleLabel && largeSubtitle.length) {   // nur Text tauschen -> kein Springen
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
    if (_headerAccessory != headerAccessory) [_headerAccessory removeFromSuperview];
    _headerAccessory = headerAccessory;
    if (self.isViewLoaded) [self updateLargeHeader];
}

- (void)updateLargeHeader {
    CGFloat w = self.tableView.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width;
    CGFloat x = [BVGTheme cardInset] + 6;
    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    CGFloat y = 8;

    if (self.headerAccessory) {
        CGRect f = self.headerAccessory.frame;
        f.origin = CGPointMake(0, y);
        f.size.width = w;
        self.headerAccessory.frame = f;
        self.headerAccessory.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addSubview:self.headerAccessory];
        y += f.size.height + 4;
    }
    if (self.largeSubtitle.length) {
        self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w - 2 * x, 16)];
        self.subtitleLabel.font = [BVGTheme font:12 weight:UIFontWeightMedium];
        self.subtitleLabel.textColor = self.largeSubtitleColor ?: [BVGTheme textSecondary];
        self.subtitleLabel.text = self.largeSubtitle;
        self.subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addSubview:self.subtitleLabel];
        y += 18;
    } else {
        self.subtitleLabel = nil;
    }
    header.frame = CGRectMake(0, 0, w, MAX(y, 6));
    self.tableView.tableHeaderView = header;
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
    ps.paragraphSpacing = 4;
    if (icon)  [s appendAttributedString:[[NSAttributedString alloc] initWithString:[icon stringByAppendingString:@"\n"]
        attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:34], NSParagraphStyleAttributeName: ps }]];
    if (title) [s appendAttributedString:[[NSAttributedString alloc] initWithString:[title stringByAppendingString:@"\n"]
        attributes:@{ NSFontAttributeName: [BVGTheme font:16 weight:UIFontWeightSemibold],
                      NSForegroundColorAttributeName: [BVGTheme textPrimary], NSParagraphStyleAttributeName: ps }]];
    if (text)  [s appendAttributedString:[[NSAttributedString alloc] initWithString:text
        attributes:@{ NSFontAttributeName: [BVGTheme font:13 weight:UIFontWeightRegular],
                      NSForegroundColorAttributeName: [BVGTheme textSecondary], NSParagraphStyleAttributeName: ps }]];
    l.attributedText = s;
    CGFloat w = v.bounds.size.width - 64;
    CGSize size = [l sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
    CGFloat top = self.tableView.tableHeaderView.frame.size.height;
    CGFloat free = v.bounds.size.height - top;
    l.frame = CGRectMake(32, top + MAX(24, free * 0.35 - size.height / 2), w, size.height);
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:l];
    self.tableView.backgroundView = v;
}

#pragma mark - Abschnittstitel & -fuss

+ (UILabel *)sectionLabelWithText:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = [text uppercaseString];
    l.font = [BVGTheme font:12 weight:UIFontWeightSemibold];
    l.textColor = [BVGTheme textSecondary];
    l.accessibilityTraits = UIAccessibilityTraitHeader;
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
    if ([self headerTitleFor:section].length) return 34;
    return section == 0 ? 4 : 12;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self headerTitleFor:section];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, title.length ? 34 : 4)];
    if (!title.length) return v;
    UILabel *l = [CardTableViewController sectionLabelWithText:title];
    l.frame = CGRectMake([BVGTheme cardInset] + 6, 14, v.bounds.size.width - 2 * [BVGTheme cardInset] - 12, 16);
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:l];
    return v;
}

- (CGFloat)footerTextHeight:(NSString *)text {
    CGFloat w = self.tableView.bounds.size.width - 2 * ([BVGTheme cardInset] + 6);
    CGRect r = [text boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{ NSFontAttributeName: [BVGTheme font:12 weight:UIFontWeightRegular] }
                                  context:nil];
    return ceil(r.size.height);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self footerTitleFor:section];
    return text.length ? [self footerTextHeight:text] + 12 : 0.01;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self footerTitleFor:section];
    if (!text.length) return [[UIView alloc] initWithFrame:CGRectZero];
    CGFloat h = [self footerTextHeight:text];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, h + 12)];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake([BVGTheme cardInset] + 6, 6,
                                                           v.bounds.size.width - 2 * ([BVGTheme cardInset] + 6), h)];
    l.numberOfLines = 0;
    l.font = [BVGTheme font:12 weight:UIFontWeightRegular];
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
