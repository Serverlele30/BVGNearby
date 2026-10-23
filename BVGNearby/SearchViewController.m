#import "SearchViewController.h"
#import "StopViewController.h"
#import "BVGAPI.h"
#import "BVGSettings.h"

@interface SearchViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *results;
@property (nonatomic, copy) NSString *lastQuery;
@property (nonatomic, assign) BOOL searching;
@property (nonatomic, assign) BOOL focusedOnce;
@end

@implementation SearchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.results = @[];
    self.tableView.rowHeight = 52;

    // Suchfeld: weisses, abgerundetes Feld auf hellgrauem Grund
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 40)];
    self.searchBar.placeholder = self.allowAddresses ? @"Haltestelle oder Adresse" : @"Haltestelle, z. B. Alexanderplatz";
    self.searchBar.delegate = self;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.backgroundImage = [BVGTheme imageWithColor:[BVGTheme background]];
    [self.searchBar setSearchFieldBackgroundImage:[BVGTheme roundedImageWithColor:[BVGTheme searchField] radius:9]
                                         forState:UIControlStateNormal];
    self.searchBar.searchTextPositionAdjustment = UIOffsetMake(6, 0);
    self.searchBar.tintColor = [BVGTheme textPrimary];
    self.searchBar.layoutMargins = UIEdgeInsetsMake(0, [BVGTheme cardInset] - 8, 0, [BVGTheme cardInset] - 8);
    self.headerAccessory = self.searchBar;

    if (self.pickHandler) self.navigationItem.title = self.pickTitle ?: @"Ort wählen";
    else self.navigationItem.title = @"Haltestelle suchen";
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    [[NSNotificationCenter defaultCenter] addObserver:self.tableView selector:@selector(reloadData)
                                                 name:BVGFavoritesChangedNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];   // "Zuletzt" aktualisieren
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.focusedOnce) {       // nur beim ersten Oeffnen direkt lostippen
        self.focusedOnce = YES;
        [self.searchBar becomeFirstResponder];
    }
}

- (BOOL)isSearching {
    return self.searchBar.text.length >= 2;
}

#pragma mark - Suche

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    if (searchText.length < 2) {
        self.results = @[];
        [self.tableView reloadData];
        return;
    }
    [self performSelector:@selector(runSearch) withObject:nil afterDelay:0.35];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self runSearch];
}

- (void)runSearch {
    NSString *q = self.searchBar.text;
    if (q.length < 2) return;
    self.lastQuery = q;
    self.searching = YES;
    NSString *path = [NSString stringWithFormat:(self.allowAddresses
                          ? @"/locations?query=%@&results=15&poi=false&addresses=true&fuzzy=true"
                          : @"/locations?query=%@&results=15&poi=false&addresses=false&fuzzy=true"),
                      [BVGAPI encode:q]];

    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        NSMutableArray *stops = [NSMutableArray array];
        if ([json isKindOfClass:[NSArray class]]) {
            for (NSDictionary *l in json) {
                if (![l isKindOfClass:[NSDictionary class]]) continue;
                BOOL isStop = [SearchViewController isStop:l] && NN(l[@"name"]);
                BOOL isAddress = self.allowAddresses && ![SearchViewController isStop:l]
                                 && NN(l[@"address"]) && NN(l[@"latitude"]) && NN(l[@"longitude"]);
                if (isStop || isAddress) [stops addObject:l];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![q isEqualToString:self.lastQuery]) return;   // veraltete Antwort
            self.searching = NO;
            self.results = stops;
            [self.tableView reloadData];
        });
    }];
}

+ (NSString *)productsText:(NSDictionary *)stop {
    NSDictionary *p = NN(stop[@"products"]);
    if (![p isKindOfClass:[NSDictionary class]]) return @"Haltestelle";
    NSMutableArray *list = [NSMutableArray array];
    NSArray *order = @[@[@"suburban", @"S-Bahn"], @[@"subway", @"U-Bahn"], @[@"tram", @"Tram"],
                       @[@"bus", @"Bus"], @[@"ferry", @"Fähre"], @[@"regional", @"Regio"], @[@"express", @"Fernverkehr"]];
    for (NSArray *pair in order) if ([NN(p[pair[0]]) boolValue]) [list addObject:pair[1]];
    return list.count ? [list componentsJoinedByString:@" · "] : @"Haltestelle";
}

// runde Marke links in der Liste (Adresse, Standort, Zuhause ...)
+ (UIImage *)iconWithText:(NSString *)text color:(UIColor *)bg {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    NSString *key = [NSString stringWithFormat:@"%@|%@", text, bg];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;

    CGSize size = CGSizeMake(28, 28);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [bg setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 28, 28)] fill];
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
                             NSForegroundColorAttributeName: [BVGTheme textPrimary] };
    CGSize t = [text sizeWithAttributes:attrs];
    [text drawAtPoint:CGPointMake((28 - t.width) / 2, (28 - t.height) / 2) withAttributes:attrs];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [cache setObject:img forKey:key];
    return img;
}

// Haltestelle oder Adresse? Massgeblich ist "type" - Adressen haben bei HAFAS ebenfalls eine id!
// Favoriten/Verlauf haben kein "type", dort sind immer Haltestellen mit id gespeichert.
+ (BOOL)isStop:(NSDictionary *)l {
    NSString *type = NN(l[@"type"]);
    if (type) return [type isEqualToString:@"stop"] || [type isEqualToString:@"station"];
    return NN(l[@"id"]) != nil && NN(l[@"latitude"]) == nil;
}

// Haltestelle -> {id, name}; Adresse -> {name, latitude, longitude} (ohne NSNull, damit speicherbar)
+ (NSDictionary *)placeFromLocation:(NSDictionary *)l {
    NSString *name = NN(l[@"name"]) ?: NN(l[@"address"]) ?: @"Ort";
    if ([SearchViewController isStop:l]) return @{ @"id": l[@"id"], @"name": name };
    // Adressen haben bei HAFAS auch eine id - die ist aber keine Haltestellen-ID, also weglassen
    NSDictionary *loc = [NN(l[@"location"]) isKindOfClass:[NSDictionary class]] ? l[@"location"] : l;
    return @{ @"name": name,
              @"latitude": NN(loc[@"latitude"]) ?: @0,
              @"longitude": NN(loc[@"longitude"]) ?: @0 };
}

#pragma mark - Daten

// Zeilen: normale Orte, oder Schnellauswahl {kind: current|saved, title, place}
- (NSArray *)sections {
    if ([self isSearching]) return @[ @{ @"title": self.results.count ? @"Treffer" : @"", @"rows": self.results } ];
    NSMutableArray *s = [NSMutableArray array];

    if (self.pickHandler && (self.offerCurrentLocation || self.offerSavedPlaces)) {
        NSMutableArray *quick = [NSMutableArray array];
        if (self.offerCurrentLocation) [quick addObject:@{ @"kind": @"current", @"title": @"Mein Standort" }];
        if (self.offerSavedPlaces) {
            for (NSArray *pl in @[@[@"home", @"Zuhause"], @[@"work", @"Arbeit"]]) {
                NSDictionary *place = [BVGSettings placeForKey:pl[0]];
                if (place) [quick addObject:@{ @"kind": @"saved", @"key": pl[0], @"title": pl[1], @"place": place }];
            }
        }
        if (quick.count) [s addObject:@{ @"title": @"", @"rows": quick }];
    }

    NSArray *favs = [BVGAPI favorites];
    NSArray *recents = [BVGAPI recentStops];
    if (favs.count)    [s addObject:@{ @"title": @"Favoriten", @"rows": favs }];
    if (recents.count) [s addObject:@{ @"title": @"Zuletzt angesehen", @"rows": recents }];
    return s;
}

- (NSDictionary *)stopAt:(NSIndexPath *)ip {
    return [self sections][ip.section][@"rows"][ip.row];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger n = [self sections].count;
    BOOL empty = (n == 0) || ([self isSearching] && !self.results.count);
    if (empty && !self.searching) {
        if ([self isSearching]) {
            [self showEmptyIcon:@"🤷" title:@"Nichts gefunden" text:@"Prüfe die Schreibweise oder versuche einen Teil des Namens."];
        } else {
            [self showEmptyIcon:nil title:@"Wohin soll's gehen?"
                           text:@"Tippe mindestens zwei Buchstaben. Mit ☆ gemerkte Haltestellen erscheinen hier und auf der Startseite."];
        }
    } else {
        [self showEmptyIcon:nil title:nil text:nil];
    }
    return n;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *t = [self sections][section][@"title"];
    return t.length ? t : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[self sections][section][@"rows"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"loc"];
    if (!cell) cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"loc"];
    NSDictionary *row = [self stopAt:indexPath];
    cell.textLabel.font = [BVGTheme font:15 weight:UIFontWeightSemibold];
    cell.detailTextLabel.font = [BVGTheme font:12 weight:UIFontWeightRegular];
    cell.accessoryType = self.pickHandler ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;

    NSString *kind = row[@"kind"];
    if ([kind isEqualToString:@"current"]) {
        cell.imageView.image = [SearchViewController iconWithText:@"◉" color:[BVGTheme accentSoft]];
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = @"per GPS";
        return cell;
    }
    if ([kind isEqualToString:@"saved"]) {
        BOOL home = [row[@"key"] isEqualToString:@"home"];
        cell.imageView.image = [SearchViewController iconWithText:(home ? @"⌂" : @"✱") color:[BVGTheme accentSoft]];
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = row[@"place"][@"name"];
        return cell;
    }

    BOOL isAddress = ![SearchViewController isStop:row];
    if (isAddress) cell.imageView.image = [SearchViewController iconWithText:@"⌂" color:[BVGTheme background]];
    else           cell.imageView.image = [BVGAPI stopSignWithSize:28];
    cell.textLabel.text = NN(row[@"name"]) ?: NN(row[@"address"]);
    NSString *detail = isAddress ? @"Adresse" : [SearchViewController productsText:row];
    if (!isAddress && [BVGAPI isFavorite:row[@"id"]]) detail = [@"★ " stringByAppendingString:detail];
    cell.detailTextLabel.text = detail;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchBar resignFirstResponder];
    NSDictionary *row = [self stopAt:indexPath];

    if (self.pickHandler) {
        NSString *kind = row[@"kind"];
        if ([kind isEqualToString:@"current"])    self.pickHandler(nil);
        else if ([kind isEqualToString:@"saved"]) self.pickHandler(row[@"place"]);
        else                                      self.pickHandler([SearchViewController placeFromLocation:row]);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (![SearchViewController isStop:row]) return;   // Adressen haben keine Abfahrten
    StopViewController *vc = [[StopViewController alloc] initWithStopId:row[@"id"] name:row[@"name"]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
