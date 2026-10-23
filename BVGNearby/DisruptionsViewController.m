#import "DisruptionsViewController.h"
#import "BVGAPI.h"

@interface DisruptionsViewController ()
@property (nonatomic, strong) NSArray *stops;
@end

@implementation DisruptionsViewController

+ (NSArray *)collectFromStops:(NSArray *)stops {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *stop in stops) {
        NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
        NSMutableArray *order = [NSMutableArray array];
        for (NSDictionary *d in stop[@"departures"] ?: @[]) {
            id remarks = NN(d[@"remarks"]);
            if (![remarks isKindOfClass:[NSArray class]]) continue;
            NSString *line = NN(NN(d[@"line"])[@"name"]);
            for (NSDictionary *r in remarks) {
                if (![r isKindOfClass:[NSDictionary class]] || ![NN(r[@"type"]) isEqualToString:@"warning"]) continue;
                NSString *summary = NN(r[@"summary"]) ?: @"Hinweis";
                NSString *text = NN(r[@"text"]) ?: @"";
                NSString *key = [summary stringByAppendingString:text];
                NSMutableDictionary *item = byKey[key];
                if (!item) {
                    item = [@{ @"summary": summary, @"text": text, @"lines": [NSMutableOrderedSet orderedSet] } mutableCopy];
                    byKey[key] = item;
                    [order addObject:key];
                }
                if (line) [item[@"lines"] addObject:line];
            }
        }
        if (!order.count) continue;
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *k in order) [items addObject:byKey[k]];
        [result addObject:@{ @"name": stop[@"name"] ?: @"?", @"items": items }];
    }
    return result;
}

+ (NSInteger)countInCollection:(NSArray *)collection {
    NSMutableSet *unique = [NSMutableSet set];
    for (NSDictionary *s in collection) for (NSDictionary *i in s[@"items"]) [unique addObject:i[@"summary"]];
    return unique.count;
}

+ (NSString *)plain:(NSString *)s {
    if (!s.length) return @"";
    NSString *t = [s stringByReplacingOccurrencesOfString:@"<br */?>" withString:@"\n"
                                                  options:NSRegularExpressionSearch | NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
    t = [t stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, t.length)];
    return [[t stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (instancetype)initWithStops:(NSArray *)stops {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) _stops = stops;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.largeTitle = @"Hinweise";
    NSInteger n = [DisruptionsViewController countInCollection:self.stops];
    self.largeSubtitle = n == 1 ? @"1 aktuelle Meldung" : [NSString stringWithFormat:@"%ld aktuelle Meldungen", (long)n];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    if (!self.stops.count) [self showEmptyIcon:@"✅" title:@"Alles ruhig" text:@"Keine Störungen an deinen Haltestellen."];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.stops.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.stops[section][@"name"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.stops[section][@"items"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CardCell *cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *item = self.stops[indexPath.section][@"items"][indexPath.row];
    NSArray *lines = [item[@"lines"] array];

    cell.textLabel.text = [@"⚠︎  " stringByAppendingString:item[@"summary"]];
    cell.textLabel.font = [BVGTheme font:16 weight:UIFontWeightSemibold];
    cell.textLabel.numberOfLines = 0;

    NSString *body = [DisruptionsViewController plain:item[@"text"]];
    if (body.length > 160) body = [[body substringToIndex:157] stringByAppendingString:@" …"];
    NSString *lineText = lines.count ? [NSString stringWithFormat:@"Betrifft: %@\n", [lines componentsJoinedByString:@", "]] : @"";
    cell.detailTextLabel.text = [lineText stringByAppendingString:body];
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.stops[indexPath.section][@"items"][indexPath.row];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:item[@"summary"]
                                                               message:[DisruptionsViewController plain:item[@"text"]]
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
