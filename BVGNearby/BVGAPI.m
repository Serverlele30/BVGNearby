#import "BVGAPI.h"
#import "BVGSettings.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreSpotlight/CoreSpotlight.h>
#import <MobileCoreServices/MobileCoreServices.h>

static NSString * const kOwnBase      = @"https://api.serverlele.de/live_navi/v6";   // eigenes Backend (schlank, gecacht)
static NSString * const kPublicBase   = @"https://v6.bvg.transport.rest";            // oeffentlicher Rueckfall
static NSString *gLastSource = nil;
static NSString * const kFavoritesKey = @"favorites";
static NSString * const kRecentsKey   = @"recentStops";
static NSString * const kSpotlightPrefix = @"stop:";
static NSString * const kAppGroup = @"group.com.serverlele.BVGNearby";   // gemeinsam mit dem Widget

NSString * const BVGFavoritesChangedNotification = @"BVGFavoritesChanged";
NSString * const BVGAlarmsChangedNotification    = @"BVGAlarmsChanged";

@implementation BVGAPI

#pragma mark - Netzwerk

+ (NSURLSession *)session {
    static NSURLSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForRequest = 15;
        c.HTTPMaximumConnectionsPerHost = 4;          // 4S: nicht zu viele parallele Verbindungen
        c.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        c.HTTPAdditionalHeaders = @{ @"User-Agent": @"BVGNearby/1.0 (iOS 9; private app)" };
        s = [NSURLSession sessionWithConfiguration:c];
    });
    return s;
}

+ (void)networkActivity:(NSInteger)delta {
    static NSInteger running = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        running = MAX(0, running + delta);
        [UIApplication sharedApplication].networkActivityIndicatorVisible = running > 0;
    });
}

+ (void)getJSON:(NSString *)path completion:(void (^)(id json, NSError *error))completion {
    [self getJSON:path attempt:0 completion:completion];
}

+ (NSArray *)bases {
    return [BVGSettings useOwnServer] ? @[kOwnBase, kPublicBase] : @[kPublicBase];
}

+ (NSString *)lastSource {
    return gLastSource;
}

// attempt 0 = erster Server; bei Fehler sofort der naechste Server, bei nur einem Server
// ein zweiter Versuch nach 1,5 s. Max. zwei Versuche.
+ (void)getJSON:(NSString *)path attempt:(NSInteger)attempt completion:(void (^)(id json, NSError *error))completion {
    NSArray *bases = [self bases];
    NSString *base = bases[MIN((NSUInteger)attempt, bases.count - 1)];
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:path]];
    if (!url) { completion(nil, nil); return; }

    [self networkActivity:+1];
    [[[self session] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        [self networkActivity:-1];
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        BOOL own = [base isEqualToString:kOwnBase];

        // Rueckfall: Netzwerkfehler, Server ueberlastet - beim eigenen Server auch 404 (Route evtl. noch nicht deployt)
        BOOL failed = error || status >= 500 || status == 429 || (own && status == 404);
        if (failed && attempt == 0) {
            if (bases.count > 1) {
                NSLog(@"%@ -> Rueckfall auf transport.rest (%@)", base, error ?: @(status));
                [self getJSON:path attempt:1 completion:completion];
            } else {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self getJSON:path attempt:1 completion:completion];
                });
            }
            return;
        }
        if (!failed) gLastSource = own ? @"serverlele" : @"transport.rest";

        id json = nil;
        if (data && !error) json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        completion(json, error);
    }] resume];
}

// Fuer URL-Pfade und -Parameter: nur ASCII-Buchstaben/Ziffern bleiben unkodiert
// (sonst liefert NSURL bei Umlauten nil). Nimmt auch NSNumber/NSNull entgegen.
+ (NSString *)encode:(id)value {
    NSString *s = nil;
    if ([value isKindOfClass:[NSString class]]) s = value;
    else if (value && value != [NSNull null]) s = [value description];
    if (!s.length) return @"";
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    });
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

#pragma mark - Zeit

+ (NSDateFormatter *)isoFormatter {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";   // NSISO8601DateFormatter erst ab iOS 10
    });
    return f;
}

+ (NSDate *)dateFromISO:(id)value {
    NSString *s = NN(value);
    if (![s isKindOfClass:[NSString class]]) return nil;
    @synchronized (self) { return [[self isoFormatter] dateFromString:s]; }
}

+ (NSString *)isoFromDate:(NSDate *)date {
    @synchronized (self) { return [[self isoFormatter] stringFromDate:date]; }
}

+ (NSString *)hhmm:(NSDate *)date {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"HH:mm";
    });
    return date ? [f stringFromDate:date] : @"–";
}

+ (NSDate *)whenOfDeparture:(NSDictionary *)d {
    return [self dateFromISO:d[@"when"]] ?: [self dateFromISO:d[@"plannedWhen"]];
}

#pragma mark - Farben & Bilder

+ (UIColor *)bvgYellow {
    return [UIColor colorWithRed:247 / 255.0 green:209 / 255.0 blue:23 / 255.0 alpha:1];
}

+ (UIColor *)bvgBlue {
    return [UIColor colorWithRed:0.07 green:0.36 blue:0.66 alpha:1];
}

+ (UIColor *)colorFromHex:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *h = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (h.length != 6) return nil;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:h] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1];
}

+ (UIColor *)colorForProduct:(NSString *)product {
    if ([product isEqualToString:@"suburban"]) return [UIColor colorWithRed:0.00 green:0.55 blue:0.24 alpha:1];
    if ([product isEqualToString:@"subway"])   return [UIColor colorWithRed:0.07 green:0.36 blue:0.66 alpha:1];
    if ([product isEqualToString:@"tram"])     return [UIColor colorWithRed:0.80 green:0.04 blue:0.13 alpha:1];
    if ([product isEqualToString:@"bus"])      return [UIColor colorWithRed:0.58 green:0.15 blue:0.43 alpha:1];
    if ([product isEqualToString:@"ferry"])    return [UIColor colorWithRed:0.00 green:0.50 blue:0.73 alpha:1];
    if ([product isEqualToString:@"regional"] || [product isEqualToString:@"express"])
                                               return [UIColor colorWithRed:0.89 green:0.00 blue:0.10 alpha:1];
    return [UIColor darkGrayColor];
}

+ (UIColor *)colorForLine:(NSDictionary *)line {
    NSDictionary *c = NN(line[@"color"]);
    UIColor *bg = [c isKindOfClass:[NSDictionary class]] ? [self colorFromHex:NN(c[@"bg"])] : nil;
    return bg ?: [self colorForProduct:NN(line[@"product"]) ?: @""];
}

+ (UIImage *)badgeForLine:(NSDictionary *)line {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });

    NSString *name    = NN(line[@"name"]) ?: @"?";
    NSString *product = NN(line[@"product"]) ?: @"";
    NSDictionary *c   = NN(line[@"color"]);
    UIColor *fg = [c isKindOfClass:[NSDictionary class]] ? [self colorFromHex:NN(c[@"fg"])] : nil;

    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", name, product, c];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;

    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightBold],
                             NSForegroundColorAttributeName: fg ?: [UIColor whiteColor] };
    CGSize textSize = [name sizeWithAttributes:attrs];
    CGSize size = CGSizeMake(MAX(38, ceil(textSize.width) + 12), 22);

    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    // S-Bahn rund, U-Bahn fast eckig, Rest leicht abgerundet - wie auf den Anzeigen
    CGFloat radius = [product isEqualToString:@"suburban"] ? size.height / 2
                   : ([product isEqualToString:@"subway"] ? 3 : 5);
    [[self colorForLine:line] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:radius] fill];
    [name drawAtPoint:CGPointMake((size.width - textSize.width) / 2, (size.height - textSize.height) / 2)
       withAttributes:attrs];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    [cache setObject:img forKey:key];
    return img;
}

+ (UIImage *)badgeStripForLines:(NSArray *)lines {
    NSMutableArray *imgs = [NSMutableArray array];
    CGFloat width = 0;
    for (NSDictionary *l in lines) {
        UIImage *b = [self badgeForLine:l];
        if (width + b.size.width > 210) break;
        [imgs addObject:b];
        width += b.size.width + 4;
    }
    if (!imgs.count) return nil;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width - 4, 22), NO, 0);
    CGFloat x = 0;
    for (UIImage *b in imgs) {
        [b drawAtPoint:CGPointMake(x, 0)];
        x += b.size.width + 4;
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (NSString *)shortName:(NSString *)name {
    if (![name isKindOfClass:[NSString class]] || !name.length) return name;
    return [name stringByReplacingOccurrencesOfString:@"\\s*\\((Berlin|Bln)\\)" withString:@""
                                              options:NSRegularExpressionSearch range:NSMakeRange(0, name.length)];
}

+ (NSString *)platform:(NSString *)platform {
    if (![platform isKindOfClass:[NSString class]] || !platform.length) return nil;
    NSString *p = [platform stringByReplacingOccurrencesOfString:@"\\s*\\(.*\\)" withString:@""
                                                          options:NSRegularExpressionSearch range:NSMakeRange(0, platform.length)];
    return p.length ? p : platform;
}

+ (UIBarButtonItem *)barButtonWithIcon:(NSString *)icon target:(id)target action:(SEL)action {
    return [[UIBarButtonItem alloc] initWithImage:[self smallIconNamed:icon size:22]
                                            style:UIBarButtonItemStylePlain target:target action:action];
}

+ (NSString *)spokenLineName:(NSDictionary *)line {
    NSString *name = NN(line[@"name"]) ?: @"";
    NSString *product = NN(line[@"product"]) ?: @"";
    if ([product isEqualToString:@"bus"])   return [@"Bus " stringByAppendingString:name];
    if ([product isEqualToString:@"tram"])  return [@"Tram " stringByAppendingString:name];
    if ([product isEqualToString:@"ferry"]) return [@"Fähre " stringByAppendingString:name];
    return name;
}

+ (UIImage *)dotWithColor:(UIColor *)color filled:(BOOL)filled {
    CGSize size = CGSizeMake(14, 14);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(2, 2, 10, 10)];
    p.lineWidth = 2.5;
    if (filled) { [color setFill]; [p fill]; }
    else { [[UIColor whiteColor] setFill]; [p fill]; [color setStroke]; [p stroke]; }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)smallIconNamed:(NSString *)name size:(CGFloat)size {
    UIImage *big = [self tabIconNamed:name];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [big drawInRect:CGRectMake(0, 0, size, size)];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Haltestellenschild: gelber Kreis mit gruenem "H" (wie an jeder deutschen Haltestelle)
+ (UIImage *)stopSignWithSize:(CGFloat)d {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    NSNumber *key = @(d);
    UIImage *img = [cache objectForKey:key];
    if (img) return img;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(d, d), NO, 0);
    UIColor *green = [UIColor colorWithRed:0 green:0.46 blue:0.25 alpha:1];
    [green setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] fill];
    [[UIColor colorWithRed:0.94 green:0.84 blue:0.13 alpha:1] setFill];
    CGFloat ring = MAX(1.5, d * 0.07);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(ring, ring, d - 2 * ring, d - 2 * ring)] fill];
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:d * 0.6 weight:UIFontWeightHeavy],
                             NSForegroundColorAttributeName: green };
    CGSize t = [@"H" sizeWithAttributes:attrs];
    [@"H" drawAtPoint:CGPointMake((d - t.width) / 2, (d - t.height) / 2) withAttributes:attrs];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [cache setObject:img forKey:key];
    return img;
}

+ (UIImage *)tabIconNamed:(NSString *)name {
    CGSize size = CGSizeMake(25, 25);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [[UIColor blackColor] set];

    if ([name isEqualToString:@"nearby"]) {
        UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, 19, 19)];
        ring.lineWidth = 2;
        [ring stroke];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(9, 9, 7, 7)] fill];
    } else if ([name isEqualToString:@"search"]) {
        UIBezierPath *glass = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, 14, 14)];
        glass.lineWidth = 2.2;
        [glass stroke];
        UIBezierPath *handle = [UIBezierPath bezierPath];
        [handle moveToPoint:CGPointMake(15, 15)];
        [handle addLineToPoint:CGPointMake(22, 22)];
        handle.lineWidth = 3;
        handle.lineCapStyle = kCGLineCapRound;
        [handle stroke];
    } else if ([name isEqualToString:@"map"]) {
        UIBezierPath *fold = [UIBezierPath bezierPath];
        [fold moveToPoint:CGPointMake(2, 6)];
        [fold addLineToPoint:CGPointMake(9, 3)];
        [fold addLineToPoint:CGPointMake(16, 6)];
        [fold addLineToPoint:CGPointMake(23, 3)];
        [fold addLineToPoint:CGPointMake(23, 19)];
        [fold addLineToPoint:CGPointMake(16, 22)];
        [fold addLineToPoint:CGPointMake(9, 19)];
        [fold addLineToPoint:CGPointMake(2, 22)];
        [fold closePath];
        [fold moveToPoint:CGPointMake(9, 3)];
        [fold addLineToPoint:CGPointMake(9, 19)];
        [fold moveToPoint:CGPointMake(16, 6)];
        [fold addLineToPoint:CGPointMake(16, 22)];
        fold.lineWidth = 1.8;
        fold.lineJoinStyle = kCGLineJoinRound;
        [fold stroke];
    } else if ([name isEqualToString:@"route"]) {
        UIBezierPath *a = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(2, 16, 7, 7)];
        a.lineWidth = 2;
        [a stroke];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(16, 2, 7, 7)] fill];
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(8, 17)];
        [path addCurveToPoint:CGPointMake(17, 8) controlPoint1:CGPointMake(18, 17) controlPoint2:CGPointMake(7, 8)];
        path.lineWidth = 2;
        path.lineCapStyle = kCGLineCapRound;
        CGFloat dash[] = {3, 3};
        [path setLineDash:dash count:2 phase:0];
        [path stroke];
    } else if ([name isEqualToString:@"speaker"]) {
        // Lautsprecher mit zwei Schallboegen
        UIBezierPath *body = [UIBezierPath bezierPath];
        [body moveToPoint:CGPointMake(3, 9)];
        [body addLineToPoint:CGPointMake(7, 9)];
        [body addLineToPoint:CGPointMake(12, 4)];
        [body addLineToPoint:CGPointMake(12, 21)];
        [body addLineToPoint:CGPointMake(7, 16)];
        [body addLineToPoint:CGPointMake(3, 16)];
        [body closePath];
        [body fill];
        for (int i = 0; i < 2; i++) {
            CGFloat r = 5 + i * 4.5;
            UIBezierPath *wave = [UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 12.5) radius:r
                                                            startAngle:-M_PI / 3.5 endAngle:M_PI / 3.5 clockwise:YES];
            wave.lineWidth = 2;
            wave.lineCapStyle = kCGLineCapRound;
            [wave stroke];
        }
    } else if ([name isEqualToString:@"locate"]) {
        // Ortungspfeil (wie in Apple Karten)
        UIBezierPath *arrow = [UIBezierPath bezierPath];
        [arrow moveToPoint:CGPointMake(22, 3)];
        [arrow addLineToPoint:CGPointMake(3, 11.5)];
        [arrow addLineToPoint:CGPointMake(12, 13)];
        [arrow addLineToPoint:CGPointMake(13.5, 22)];
        [arrow closePath];
        arrow.lineWidth = 2;
        arrow.lineJoinStyle = kCGLineJoinRound;
        [arrow stroke];
    } else if ([name isEqualToString:@"more"]) {
        for (int i = 0; i < 3; i++) {
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(3 + i * 7.5, 10, 4.5, 4.5)] fill];
        }
    } else if ([name isEqualToString:@"alarm"]) {
        UIBezierPath *face = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 4, 19, 19)];
        face.lineWidth = 2;
        [face stroke];
        UIBezierPath *hands = [UIBezierPath bezierPath];
        [hands moveToPoint:CGPointMake(12.5, 7.5)];
        [hands addLineToPoint:CGPointMake(12.5, 13.5)];
        [hands addLineToPoint:CGPointMake(17, 16)];
        hands.lineWidth = 2;
        hands.lineCapStyle = kCGLineCapRound;
        hands.lineJoinStyle = kCGLineJoinRound;
        [hands stroke];
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - Favoriten

+ (NSArray *)favorites {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:kFavoritesKey] ?: @[];
}

+ (BOOL)isFavorite:(NSString *)stopId {
    for (NSDictionary *f in [self favorites]) if ([f[@"id"] isEqualToString:stopId]) return YES;
    return NO;
}

+ (void)setFavorite:(BOOL)fav stopId:(NSString *)stopId name:(NSString *)name {
    if (!stopId) return;
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *f in [self favorites]) if (![f[@"id"] isEqualToString:stopId]) [list addObject:f];
    if (fav) [list addObject:@{ @"id": stopId, @"name": name ?: @"?" }];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kFavoritesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (fav) [self indexStopInSpotlight:stopId name:name];
    [self syncWidget];
    [[NSNotificationCenter defaultCenter] postNotificationName:BVGFavoritesChangedNotification object:nil];
}

+ (void)syncWidget {
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:kAppGroup];
    [shared setObject:[self favorites] forKey:@"favorites"];
    [shared setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"set.ownServer"] forKey:@"ownServer"];
    [shared synchronize];
}

#pragma mark - Zuletzt angesehen

+ (NSArray *)recentStops {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:kRecentsKey] ?: @[];
}

+ (void)addRecentStop:(NSString *)stopId name:(NSString *)name {
    if (!stopId || !name) return;
    NSMutableArray *list = [NSMutableArray arrayWithObject:@{ @"id": stopId, @"name": name }];
    for (NSDictionary *r in [self recentStops]) {
        if (![r[@"id"] isEqualToString:stopId] && list.count < 8) [list addObject:r];
    }
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kRecentsKey];
    [self indexStopInSpotlight:stopId name:name];
}

+ (NSString *)nameForStop:(NSString *)stopId {
    for (NSDictionary *f in [self favorites])   if ([f[@"id"] isEqualToString:stopId]) return f[@"name"];
    for (NSDictionary *r in [self recentStops]) if ([r[@"id"] isEqualToString:stopId]) return r[@"name"];
    return nil;
}

#pragma mark - Spotlight

+ (void)indexStopInSpotlight:(NSString *)stopId name:(NSString *)name {
    if (!stopId || !name || ![CSSearchableIndex isIndexingAvailable]) return;

    CSSearchableItemAttributeSet *attrs = [[CSSearchableItemAttributeSet alloc] initWithItemContentType:(__bridge NSString *)kUTTypeText];
    attrs.title = name;
    attrs.contentDescription = @"Haltestelle · Live-Abfahrten anzeigen";
    attrs.keywords = @[name, @"Abfahrt", @"Abfahrten", @"BVG", @"Haltestelle", @"Bahn", @"Bus"];

    CSSearchableItem *item = [[CSSearchableItem alloc]
        initWithUniqueIdentifier:[kSpotlightPrefix stringByAppendingString:stopId]
                domainIdentifier:@"stops"
                    attributeSet:attrs];
    [[CSSearchableIndex defaultSearchableIndex] indexSearchableItems:@[item] completionHandler:^(NSError *error) {
        if (error) NSLog(@"Spotlight-Fehler: %@", error);
    }];
}

+ (NSString *)stopIdFromSpotlightIdentifier:(NSString *)identifier {
    if (![identifier hasPrefix:kSpotlightPrefix]) return nil;
    return [identifier substringFromIndex:kSpotlightPrefix.length];
}

#pragma mark - Sprachausgabe

+ (AVSpeechSynthesizer *)synth {
    static AVSpeechSynthesizer *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[AVSpeechSynthesizer alloc] init]; });
    return s;
}

+ (void)speak:(NSString *)text {
    if (!text.length || ![BVGSettings speechEnabled]) return;
    // Ambient: respektiert den Stummschalter -> bei "stumm" bleibt die Ansage still
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    [[self synth] stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
    u.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"de-DE"];
    u.rate = AVSpeechUtteranceDefaultSpeechRate;
    u.postUtteranceDelay = 0.2;
    [[self synth] speakUtterance:u];
}

+ (void)stopSpeaking {
    [[self synth] stopSpeakingAtBoundary:AVSpeechBoundaryWord];
}

+ (BOOL)isSpeaking {
    return [self synth].isSpeaking;
}

+ (NSString *)speakable:(NSString *)s {
    if (!s) return @"";
    NSDictionary *map = @{ @"S+U ": @"", @"(Berlin)": @"", @"Bhf": @"Bahnhof", @"Str.": @"Straße",
                           @"str.": @"straße", @"Pl.": @"Platz", @"/": @" ", @"  ": @" " };
    for (NSString *k in map) s = [s stringByReplacingOccurrencesOfString:k withString:map[k]];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+ (NSString *)announcementForStop:(NSString *)stopName departures:(NSArray *)deps max:(NSInteger)max {
    NSMutableArray *parts = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"Nächste Abfahrten an %@", [self speakable:stopName]]];
    NSInteger count = 0;

    for (NSDictionary *d in deps) {
        if (count >= max) break;
        NSString *line = [self spokenLineName:NN(d[@"line"])];
        NSString *dir  = [self speakable:NN(d[@"direction"])];
        NSMutableString *s = [NSMutableString stringWithFormat:@"%@ Richtung %@, ", line, dir];

        if ([NN(d[@"cancelled"]) boolValue]) {
            [s appendString:@"fällt aus"];
        } else {
            NSDate *when = [self whenOfDeparture:d];
            NSInteger mins = when ? (NSInteger)floor([when timeIntervalSinceNow] / 60.0) : -1;
            if (mins <= 0)       [s appendString:@"jetzt"];
            else if (mins == 1)  [s appendString:@"in einer Minute"];
            else if (mins < 60)  [s appendFormat:@"in %ld Minuten", (long)mins];
            else                 [s appendFormat:@"um %@ Uhr", [self hhmm:when]];

            NSInteger delay = [NN(d[@"delay"]) integerValue] / 60;
            if (delay == 1) [s appendString:@", eine Minute verspätet"];
            else if (delay > 1) [s appendFormat:@", %ld Minuten verspätet", (long)delay];
        }
        [parts addObject:s];
        count++;
    }
    if (count == 0) [parts addObject:@"Aktuell keine Abfahrten"];
    return [[parts componentsJoinedByString:@". "] stringByAppendingString:@"."];
}

#pragma mark - Wecker

+ (NSArray *)userAlarms {
    NSMutableArray *list = [NSMutableArray array];
    for (UILocalNotification *n in [[UIApplication sharedApplication] scheduledLocalNotifications]) {
        if (n.userInfo[@"kind"] == nil) [list addObject:n];   // Navigations-Hinweise ausblenden
    }
    return list;
}

// scheduledLocalNotifications ist teuer -> Trip-IDs zwischenspeichern (wichtig beim Scrollen auf dem 4S)
static NSSet *gAlarmTripIds;

+ (void)invalidateAlarmCache {
    gAlarmTripIds = nil;
}

+ (BOOL)hasAlarmForTrip:(NSString *)tripId {
    if (!tripId) return NO;
    if (!gAlarmTripIds) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
            [nc addObserver:self selector:@selector(invalidateAlarmCache) name:BVGAlarmsChangedNotification object:nil];
            [nc addObserver:self selector:@selector(invalidateAlarmCache) name:UIApplicationDidBecomeActiveNotification object:nil];
        });
        NSMutableSet *ids = [NSMutableSet set];
        for (UILocalNotification *n in [self userAlarms]) {
            if (n.userInfo[@"tripId"]) [ids addObject:n.userInfo[@"tripId"]];
        }
        gAlarmTripIds = ids;
    }
    return [gAlarmTripIds containsObject:tripId];
}

+ (void)cancelAlarmForTrip:(NSString *)tripId {
    for (UILocalNotification *n in [[UIApplication sharedApplication] scheduledLocalNotifications]) {
        if ([n.userInfo[@"tripId"] isEqualToString:tripId]) {
            [[UIApplication sharedApplication] cancelLocalNotification:n];
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:BVGAlarmsChangedNotification object:nil];
}

+ (void)presentAlarmSheetForDeparture:(NSDictionary *)d stopName:(NSString *)stopName from:(UIViewController *)vc {
    NSDate *when = [self whenOfDeparture:d];
    NSString *tripId = NN(d[@"tripId"]);
    if (!when || !tripId) return;

    NSDictionary *lineDict = NN(d[@"line"]);
    NSString *line = NN(lineDict[@"name"]) ?: @"?";
    NSString *dir  = NN(d[@"direction"]) ?: @"";
    NSInteger minutesLeft = (NSInteger)floor([when timeIntervalSinceNow] / 60.0);

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ → %@", line, dir]
                                                                   message:@"Wann soll ich dich erinnern?"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    BOOL any = NO;
    for (NSNumber *offset in @[@2, @5, @10, @15, @20]) {
        if (offset.integerValue >= minutesLeft) continue;
        any = YES;
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ min vor Abfahrt", offset]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            UILocalNotification *n = [[UILocalNotification alloc] init];
            n.fireDate = [when dateByAddingTimeInterval:-offset.integerValue * 60];
            n.alertBody = [NSString stringWithFormat:@"%@ → %@ fährt in %@ min ab %@", line, dir, offset, stopName ?: @""];
            n.soundName = UILocalNotificationDefaultSoundName;
            n.userInfo = @{ @"tripId": tripId, @"line": line, @"direction": dir,
                            @"stop": stopName ?: @"", @"departure": when };
            [[UIApplication sharedApplication] scheduleLocalNotification:n];
            [[NSNotificationCenter defaultCenter] postNotificationName:BVGAlarmsChangedNotification object:nil];
        }]];
    }
    if (!any) sheet.message = @"Die Abfahrt ist zu knapp für einen Wecker.";
    [sheet addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = vc.view;
    [vc presentViewController:sheet animated:YES completion:nil];
}

+ (NSArray *)editActionsForDeparture:(NSDictionary *)d stopName:(NSString *)stopName from:(UITableViewController *)vc {
    NSString *tripId = NN(d[@"tripId"]);
    if (!tripId) return @[];
    __weak UITableViewController *weakVC = vc;

    if ([self hasAlarmForTrip:tripId]) {
        UITableViewRowAction *off = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
                                                                       title:@"Wecker aus"
                                                                     handler:^(UITableViewRowAction *a, NSIndexPath *ip) {
            [weakVC.tableView setEditing:NO animated:YES];
            [BVGAPI cancelAlarmForTrip:tripId];
        }];
        return @[off];
    }

    UITableViewRowAction *on = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal
                                                                  title:@"Wecker"
                                                                handler:^(UITableViewRowAction *a, NSIndexPath *ip) {
        [weakVC.tableView setEditing:NO animated:YES];
        if (weakVC) [BVGAPI presentAlarmSheetForDeparture:d stopName:stopName from:weakVC];
    }];
    on.backgroundColor = [UIColor orangeColor];
    return @[on];
}

@end
