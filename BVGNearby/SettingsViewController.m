#import "SettingsViewController.h"
#import "BVGSettings.h"
#import "BVGAPI.h"
#import <CoreSpotlight/CoreSpotlight.h>
#import <objc/runtime.h>

static char kSwitchKey;   // Zuordnung UISwitch -> Einstellungs-Schluessel

@interface SettingsViewController ()
@property (nonatomic, strong) NSArray *sections;   // [{title, footer, rows:[{title, key, values, labels} | {switch}]}]
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.largeTitle = @"Einstellungen";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self action:@selector(close)];
    self.sections = @[
        @{ @"title": @"Abfahrten",
           @"rows": @[
               @{ @"title": @"Suchradius", @"key": @"set.radius",
                  @"values": @[@500, @1000, @1500], @"labels": @[@"500 m", @"1 km", @"1,5 km"] },
               @{ @"title": @"Abfahrten pro Haltestelle", @"key": @"set.perStop",
                  @"values": @[@3, @5, @8], @"labels": @[@"3", @"5", @"8"] } ] },
        @{ @"title": @"Navigation",
           @"footer": @"Umstiege werden nie mit weniger als 5 Minuten Puffer geplant. Wird der Puffer durch Verspätungen kleiner, schlägt die App eine Alternative vor.",
           @"rows": @[
               @{ @"title": @"Mindest-Umstiegszeit", @"key": @"set.transfer",
                  @"values": @[@5, @7, @10], @"labels": @[@"5 min", @"7 min", @"10 min"] },
               @{ @"title": @"Einsteigen-Hinweis", @"key": @"set.boardLead",
                  @"values": @[@1, @2, @3, @5], @"labels": @[@"1 min vorher", @"2 min vorher", @"3 min vorher", @"5 min vorher"] } ] },
        @{ @"title": @"Orte",
           @"footer": @"Festlegen oder ändern: im Route-Tab das Schnellziel gedrückt halten.",
           @"rows": @[ @{ @"title": @"🏠  Zuhause", @"place": @"home" },
                       @{ @"title": @"💼  Arbeit", @"place": @"work" } ] },
        @{ @"title": @"Ansagen",
           @"footer": @"Steht der Stummschalter auf stumm, bleiben Ansagen automatisch still und Erinnerungen vibrieren nur.",
           @"rows": @[ @{ @"title": @"Sprachansagen", @"switch": @"set.speech" } ] },
        @{ @"title": @"Info",
           @"footer": @"Eigener Server: api.serverlele.de (schlanker, gecacht). Fällt er aus, nutzt die App automatisch v6.bvg.transport.rest. Keine Gewähr.",
           @"rows": @[ @{ @"title": @"Eigener Server", @"switch": @"set.ownServer" },
                       @{ @"title": @"Daten zuletzt von", @"info": @"source" },
                       @{ @"title": @"Version", @"info": @"version" },
                       @{ @"title": @"Spotlight-Einträge löschen", @"action": @"clearSpotlight" },
                       @{ @"title": @"Verlauf löschen", @"action": @"clearRecents" } ] },
    ];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.sections[section][@"footer"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"rows"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    CardCell *cell = [[CardCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = row[@"title"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.detailTextLabel.font = [BVGTheme font:16 weight:UIFontWeightRegular];

    if (row[@"values"]) {
        // aktueller Wert rechts, Antippen oeffnet die Auswahl (wie in den iOS-Einstellungen)
        NSInteger current = [[NSUserDefaults standardUserDefaults] integerForKey:row[@"key"]];
        NSUInteger idx = [row[@"values"] indexOfObject:@(current)];
        cell.detailTextLabel.text = row[@"labels"][idx == NSNotFound ? 0 : idx];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (row[@"place"]) {
        NSDictionary *place = [BVGSettings placeForKey:row[@"place"]];
        cell.detailTextLabel.text = place ? place[@"name"] : @"nicht festgelegt";
        if (place) cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (row[@"switch"]) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:row[@"switch"]];
        objc_setAssociatedObject(sw, &kSwitchKey, row[@"switch"], OBJC_ASSOCIATION_COPY_NONATOMIC);
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (row[@"info"]) {
        if ([row[@"info"] isEqualToString:@"source"]) {
            cell.detailTextLabel.text = [BVGAPI lastSource] ?: @"–";
        } else {
            NSDictionary *info = [NSBundle mainBundle].infoDictionary;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)",
                                         info[@"CFBundleShortVersionString"] ?: @"1.0", info[@"CFBundleVersion"] ?: @"1"];
        }
    } else if (row[@"action"]) {
        cell.textLabel.textColor = [BVGTheme red];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)chooseValueForRow:(NSDictionary *)row {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row[@"title"] message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *values = row[@"values"];
    NSInteger current = [[NSUserDefaults standardUserDefaults] integerForKey:row[@"key"]];
    for (NSUInteger i = 0; i < values.count; i++) {
        NSString *title = row[@"labels"][i];
        if ([values[i] integerValue] == current) title = [@"✓  " stringByAppendingString:title];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [BVGSettings setInteger:[values[i] integerValue] forKey:row[@"key"]];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)switchChanged:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, &kSwitchKey);
    [BVGSettings setBool:sw.on forKey:key];
    if ([key isEqualToString:@"set.speech"] && !sw.on) [BVGAPI stopSpeaking];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    if (row[@"values"]) { [self chooseValueForRow:row]; return; }
    if (row[@"place"]) {
        if (![BVGSettings placeForKey:row[@"place"]]) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:row[@"title"] message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
        [a addAction:[UIAlertAction actionWithTitle:@"Ort entfernen" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [BVGSettings setPlace:nil forKey:row[@"place"]];
            [self.tableView reloadData];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = self.view;
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    NSString *action = row[@"action"];
    if (!action) return;

    if ([action isEqualToString:@"clearSpotlight"]) {
        [[CSSearchableIndex defaultSearchableIndex] deleteAllSearchableItemsWithCompletionHandler:nil];
    } else if ([action isEqualToString:@"clearRecents"]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"recentStops"];
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Erledigt" message:nil
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
