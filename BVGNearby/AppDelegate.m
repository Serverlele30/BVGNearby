#import "AppDelegate.h"
#import "ViewController.h"
#import "MapViewController.h"
#import "JourneyViewController.h"
#import "SearchViewController.h"
#import "AlarmsViewController.h"
#import "StopViewController.h"
#import "GuidanceManager.h"
#import "GuidanceViewController.h"
#import "BVGAPI.h"
#import "BVGTheme.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreSpotlight/CoreSpotlight.h>

@interface AppDelegate ()
@property (nonatomic, strong) UITabBarController *tabs;
@end

// Absturz-Melder: speichert Grund + Stack einer nicht abgefangenen Exception,
// beim naechsten Start wird beides angezeigt (iOS 9 schreibt den Grund nicht in den Crash-Report).
static NSString * const kLastCrashKey = @"lastCrash";

static void BVGUncaughtException(NSException *e) {
    NSArray *stack = e.callStackSymbols ?: @[];
    stack = [stack subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)25, stack.count))];
    NSString *report = [NSString stringWithFormat:@"%@\n%@\n\n%@", e.name, e.reason ?: @"(kein Grund)",
                        [stack componentsJoinedByString:@"\n"]];
    [[NSUserDefaults standardUserDefaults] setObject:report forKey:kLastCrashKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@implementation AppDelegate

- (void)showLastCrashIfAny {
    NSString *report = [[NSUserDefaults standardUserDefaults] stringForKey:kLastCrashKey];
    if (!report) return;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLastCrashKey];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Letzter Absturz"
                                                               message:report
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Kopieren" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [UIPasteboard generalPasteboard].string = report;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSSetUncaughtExceptionHandler(&BVGUncaughtException);
    [application registerUserNotificationSettings:
        [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge)
                                          categories:nil]];

    [BVGTheme applyAppearance];   // modernes Design (Farben, Leisten, Schriften)

    NSArray *roots = @[
        @[[[ViewController alloc] initWithStyle:UITableViewStylePlain],        @"In der Nähe", @"nearby"],
        @[[[MapViewController alloc] init],                                     @"Karte",       @"map"],
        @[[[JourneyViewController alloc] initWithStyle:UITableViewStyleGrouped], @"Route",      @"route"],
        @[[[SearchViewController alloc] initWithStyle:UITableViewStylePlain],  @"Suche",       @"search"],
        @[[[AlarmsViewController alloc] initWithStyle:UITableViewStylePlain],  @"Wecker",      @"alarm"],
    ];
    NSMutableArray *navs = [NSMutableArray array];
    NSInteger tag = 0;
    for (NSArray *r in roots) {
        UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:r[0]];
        n.tabBarItem = [[UITabBarItem alloc] initWithTitle:r[1] image:[BVGAPI tabIconNamed:r[2]] tag:tag++];
        [navs addObject:n];
    }

    self.tabs = [[UITabBarController alloc] init];
    self.tabs.viewControllers = navs;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [BVGTheme background];
    self.window.tintColor = [BVGTheme textPrimary];
    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showLastCrashIfAny];
    });

    // Favoriten in die iOS-Suche aufnehmen (falls frisch installiert)
    for (NSDictionary *f in [BVGAPI favorites]) [BVGAPI indexStopInSpotlight:f[@"id"] name:f[@"name"]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateAlarmBadge)
                                                 name:BVGAlarmsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateGuidanceBadge)
                                                 name:GuidanceChangedNotification object:nil];
    [self updateAlarmBadge];
    [GuidanceManager shared];          // laufende Navigation nach App-Neustart wiederherstellen
    [self updateGuidanceBadge];

    // App wurde durch Antippen einer Navigations-Mitteilung gestartet
    UILocalNotification *launchNote = launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
    if (launchNote.userInfo[@"kind"]) [self openGuidance];
    return YES;
}

- (void)updateGuidanceBadge {
    UIViewController *routeTab = self.tabs.viewControllers[2];
    GuidanceManager *g = [GuidanceManager shared];
    if (!g.active) routeTab.tabBarItem.badgeValue = nil;
    else routeTab.tabBarItem.badgeValue = (g.status == GuidanceStatusBroken || g.alternative) ? @"!" : @"▶";
}

- (void)openGuidance {
    if (![GuidanceManager shared].active) return;
    [self.tabs dismissViewControllerAnimated:NO completion:nil];
    self.tabs.selectedIndex = 2;
    UINavigationController *nav = (UINavigationController *)self.tabs.selectedViewController;
    if ([nav.topViewController isKindOfClass:[GuidanceViewController class]]) return;
    [nav popToRootViewControllerAnimated:NO];
    [nav pushViewController:[[GuidanceViewController alloc] initWithStyle:UITableViewStyleGrouped] animated:NO];
}

+ (NSString *)speakableNotification:(NSString *)text {
    for (NSString *icon in @[@"🚏 ", @"🔔 ", @"⚠ ", @"→"]) {
        text = [text stringByReplacingOccurrencesOfString:icon withString:([icon isEqualToString:@"→"] ? @"Richtung" : @"")];
    }
    return [text stringByReplacingOccurrencesOfString:@"Antippen zum Entscheiden." withString:@""];
}

- (void)updateAlarmBadge {
    NSUInteger count = [BVGAPI userAlarms].count;
    UIViewController *alarmsTab = self.tabs.viewControllers.lastObject;
    alarmsTab.tabBarItem.badgeValue = count ? [@(count) stringValue] : nil;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    application.applicationIconBadgeNumber = 0;
    [self updateAlarmBadge];
}

#pragma mark - Spotlight: Haltestelle aus der iOS-Suche oeffnen

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity
 restorationHandler:(void (^)(NSArray *))restorationHandler {
    if (![userActivity.activityType isEqualToString:CSSearchableItemActionType]) return NO;
    NSString *stopId = [BVGAPI stopIdFromSpotlightIdentifier:userActivity.userInfo[CSSearchableItemActivityIdentifier]];
    if (!stopId) return NO;

    [self.tabs dismissViewControllerAnimated:NO completion:nil];
    self.tabs.selectedIndex = 0;
    UINavigationController *nav = (UINavigationController *)self.tabs.selectedViewController;
    [nav popToRootViewControllerAnimated:NO];

    StopViewController *vc = [[StopViewController alloc] initWithStopId:stopId
                                                                   name:[BVGAPI nameForStop:stopId] ?: @"Haltestelle"];
    [nav pushViewController:vc animated:NO];
    return YES;
}

#pragma mark - Wecker

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    [[NSNotificationCenter defaultCenter] postNotificationName:BVGAlarmsChangedNotification object:nil];

    // Navigation: Erinnerung oder Alternative
    if (notification.userInfo[@"kind"]) {
        if (application.applicationState != UIApplicationStateActive) {   // Mitteilung angetippt
            [self openGuidance];
            return;
        }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        [BVGAPI speak:[AppDelegate speakableNotification:notification.alertBody]];   // bei Stumm: still

        BOOL isAlternative = [notification.userInfo[@"kind"] isEqualToString:@"alternative"];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:(isAlternative ? @"⚠ Route gefährdet" : @"Navigation")
                                                                   message:notification.alertBody
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:(isAlternative ? @"Ansehen & entscheiden" : @"Navigation öffnen")
                                              style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [BVGAPI stopSpeaking];
            [self openGuidance];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
            [BVGAPI stopSpeaking];
        }]];
        UIViewController *top = self.window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        if (![top isKindOfClass:[UIAlertController class]]) [top presentViewController:a animated:YES completion:nil];
        return;
    }

    if (application.applicationState != UIApplicationStateActive) return;

    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    NSDictionary *info = notification.userInfo;
    NSDate *dep = info[@"departure"];
    if (info[@"line"] && [dep isKindOfClass:[NSDate class]]) {
        NSInteger mins = MAX(1, (NSInteger)round([dep timeIntervalSinceNow] / 60.0));
        [BVGAPI speak:[NSString stringWithFormat:@"Achtung! %@ Richtung %@ fährt in %ld Minuten ab %@.",
                       info[@"line"], info[@"direction"] ?: @"", (long)mins, info[@"stop"] ?: @""]];
    } else {
        [BVGAPI speak:notification.alertBody];
    }

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"⏰ Gleich geht's los"
                                                               message:notification.alertBody
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [BVGAPI stopSpeaking];
    }]];
    UIViewController *top = self.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:a animated:YES completion:nil];
}

@end
