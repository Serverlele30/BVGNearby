#import "MapViewController.h"
#import "StopViewController.h"
#import "TripViewController.h"
#import "BVGAnnotation.h"
#import "BVGAPI.h"
#import "BVGTheme.h"
#import <MapKit/MapKit.h>

static const CLLocationDegrees kMaxRadarSpan = 0.045;   // weiter rausgezoomt -> keine Fahrzeuge (Last auf dem 4S)

@interface MapViewController () <MKMapViewDelegate>
@property (nonatomic, strong) MKMapView *map;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSMutableDictionary *vehicles;   // tripId -> BVGAnnotation
@property (nonatomic, strong) NSMutableDictionary *stops;      // stopId -> BVGAnnotation
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL centeredOnUser;
@property (nonatomic, assign) BOOL loadingVehicles;
@end

@implementation MapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Karte";
    self.vehicles = [NSMutableDictionary dictionary];
    self.stops = [NSMutableDictionary dictionary];

    self.map = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.map.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.map.delegate = self;
    self.map.showsUserLocation = YES;
    self.map.showsPointsOfInterest = NO;
    self.map.rotateEnabled = NO;
    [self.view addSubview:self.map];

    // Start: Berlin-Mitte, bis der Standort da ist
    [self.map setRegion:MKCoordinateRegionMakeWithDistance(CLLocationCoordinate2DMake(52.5208, 13.4094), 2500, 2500) animated:NO];

    // schwebende Status-Pille mit Schatten
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [BVGTheme font:12 weight:UIFontWeightMedium];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [BVGTheme textPrimary];
    self.statusLabel.backgroundColor = [UIColor whiteColor];
    self.statusLabel.layer.cornerRadius = 14;
    self.statusLabel.layer.masksToBounds = NO;
    self.statusLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    self.statusLabel.layer.shadowOpacity = 0.12;
    self.statusLabel.layer.shadowRadius = 6;
    self.statusLabel.layer.shadowOffset = CGSizeMake(0, 2);
    [self.view addSubview:self.statusLabel];

    self.navigationItem.leftBarButtonItem = [BVGAPI barButtonWithIcon:@"locate" target:self action:@selector(centerOnUser)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"Mein Standort";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self action:@selector(reloadAll)];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat bottom = self.view.bounds.size.height - self.bottomLayoutGuide.length;
    self.statusLabel.frame = CGRectMake(w / 2 - 110, bottom - 42, 220, 28);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self reloadAll];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:12 target:self selector:@selector(loadVehicles) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)centerOnUser {
    CLLocation *loc = self.map.userLocation.location;
    if (!loc) return;
    [self.map setRegion:MKCoordinateRegionMakeWithDistance(loc.coordinate, 1200, 1200) animated:YES];
}

- (void)reloadAll {
    [self loadStops];
    [self loadVehicles];
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.text = text;
    self.statusLabel.hidden = (text.length == 0);
}

#pragma mark - Haltestellen

- (void)loadStops {
    MKCoordinateRegion r = self.map.region;
    if (r.span.latitudeDelta > kMaxRadarSpan * 1.5) return;
    if (self.stops.count > 150) {   // Speicher schonen: alte Haltestellen wegwerfen
        [self.map removeAnnotations:self.stops.allValues];
        [self.stops removeAllObjects];
    }

    CLLocationDistance radius = MIN(1500, r.span.latitudeDelta * 111000 / 2);
    NSString *path = [NSString stringWithFormat:
        @"/locations/nearby?latitude=%.5f&longitude=%.5f&distance=%.0f&results=35&poi=false&addresses=false",
        r.center.latitude, r.center.longitude, radius];

    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        if (![json isKindOfClass:[NSArray class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSDictionary *s in json) {
                NSString *sid = NN(s[@"id"]);
                NSDictionary *loc = NN(s[@"location"]);
                if (!sid || self.stops[sid] || ![loc isKindOfClass:[NSDictionary class]]) continue;

                BVGAnnotation *a = [[BVGAnnotation alloc] init];
                a.kind = BVGAnnotationKindStop;
                a.identifier = sid;
                a.title = NN(s[@"name"]) ?: @"Haltestelle";
                a.subtitle = @"Abfahrten anzeigen";
                a.coordinate = CLLocationCoordinate2DMake([loc[@"latitude"] doubleValue], [loc[@"longitude"] doubleValue]);
                self.stops[sid] = a;
                [self.map addAnnotation:a];
            }
        });
    }];
}

#pragma mark - Fahrzeuge (Radar)

- (void)loadVehicles {
    MKCoordinateRegion r = self.map.region;
    if (r.span.latitudeDelta > kMaxRadarSpan) {
        [self.map removeAnnotations:self.vehicles.allValues];
        [self.vehicles removeAllObjects];
        [self setStatus:@"Hineinzoomen für Live-Fahrzeuge"];
        return;
    }
    if (self.loadingVehicles) return;
    self.loadingVehicles = YES;

    double north = r.center.latitude + r.span.latitudeDelta / 2;
    double south = r.center.latitude - r.span.latitudeDelta / 2;
    double west  = r.center.longitude - r.span.longitudeDelta / 2;
    double east  = r.center.longitude + r.span.longitudeDelta / 2;
    NSString *path = [NSString stringWithFormat:
        @"/radar?north=%.5f&west=%.5f&south=%.5f&east=%.5f&results=80&duration=30&frames=1&polylines=false",
        north, west, south, east];

    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        NSArray *movements = nil;
        if ([json isKindOfClass:[NSArray class]]) movements = json;
        else if ([json isKindOfClass:[NSDictionary class]] && [json[@"movements"] isKindOfClass:[NSArray class]]) movements = json[@"movements"];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.loadingVehicles = NO;
            if (!movements) {
                NSLog(@"Radar-Fehler: %@", error);
                [self setStatus:@"Live-Daten nicht verfügbar"];
                return;
            }
            [self applyMovements:movements];
        });
    }];
}

- (void)applyMovements:(NSArray *)movements {
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *added = [NSMutableArray array];
    NSMutableArray *moved = [NSMutableArray array];

    for (NSDictionary *m in movements) {
        NSString *tripId = NN(m[@"tripId"]);
        NSDictionary *loc = NN(m[@"location"]);
        if (!tripId || ![loc isKindOfClass:[NSDictionary class]]) continue;
        [seen addObject:tripId];

        CLLocationCoordinate2D c = CLLocationCoordinate2DMake([loc[@"latitude"] doubleValue], [loc[@"longitude"] doubleValue]);
        NSDictionary *line = NN(m[@"line"]);
        NSString *title = [NSString stringWithFormat:@"%@ → %@", NN(line[@"name"]) ?: @"?", NN(m[@"direction"]) ?: @""];

        BVGAnnotation *a = self.vehicles[tripId];
        if (a) {
            [moved addObject:@[a, [NSValue valueWithMKCoordinate:c]]];
            a.title = title;
        } else {
            a = [[BVGAnnotation alloc] init];
            a.kind = BVGAnnotationKindVehicle;
            a.identifier = tripId;
            a.line = line;
            a.title = title;
            a.subtitle = @"Fahrtverlauf anzeigen";
            a.coordinate = c;
            self.vehicles[tripId] = a;
            [added addObject:a];
        }
    }

    // verschwundene Fahrzeuge entfernen
    NSMutableArray *gone = [NSMutableArray array];
    for (NSString *tripId in self.vehicles.allKeys) {
        if (![seen containsObject:tripId]) {
            [gone addObject:self.vehicles[tripId]];
            [self.vehicles removeObjectForKey:tripId];
        }
    }
    [self.map removeAnnotations:gone];
    [self.map addAnnotations:added];

    // bekannte Fahrzeuge sanft weiterbewegen
    [UIView animateWithDuration:2.0 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        for (NSArray *pair in moved) {
            BVGAnnotation *a = pair[0];
            a.coordinate = [pair[1] MKCoordinateValue];
        }
    } completion:nil];

    [self setStatus:[NSString stringWithFormat:@"● Live · %lu Fahrzeuge · %@",
                     (unsigned long)self.vehicles.count, [BVGAPI hhmm:[NSDate date]]]];
}

#pragma mark - MKMapViewDelegate

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation {
    if (self.centeredOnUser || !userLocation.location) return;
    self.centeredOnUser = YES;
    [self.map setRegion:MKCoordinateRegionMakeWithDistance(userLocation.location.coordinate, 1200, 1200) animated:NO];
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadAll) object:nil];
    [self performSelector:@selector(reloadAll) withObject:nil afterDelay:0.7];
}

+ (UIImage *)stopIcon {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGSize size = CGSizeMake(20, 20);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0);
        UIBezierPath *c = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1, 1, 18, 18)];
        [[BVGAPI bvgYellow] setFill];
        [c fill];
        [[UIColor colorWithRed:0 green:0.45 blue:0.25 alpha:1] setStroke];
        c.lineWidth = 2;
        [c stroke];
        NSDictionary *attrs = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:12],
                                 NSForegroundColorAttributeName: [UIColor colorWithRed:0 green:0.45 blue:0.25 alpha:1] };
        CGSize t = [@"H" sizeWithAttributes:attrs];
        [@"H" drawAtPoint:CGPointMake((20 - t.width) / 2, (20 - t.height) / 2) withAttributes:attrs];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if (![annotation isKindOfClass:[BVGAnnotation class]]) return nil;   // eigener Standort: blauer Punkt
    BVGAnnotation *a = (BVGAnnotation *)annotation;

    NSString *reuse = a.kind == BVGAnnotationKindVehicle ? @"vehicle" : @"stop";
    MKAnnotationView *v = [mapView dequeueReusableAnnotationViewWithIdentifier:reuse];
    if (!v) {
        v = [[MKAnnotationView alloc] initWithAnnotation:a reuseIdentifier:reuse];
        v.canShowCallout = YES;
        v.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
    }
    v.annotation = a;

    if (a.kind == BVGAnnotationKindVehicle) {
        v.image = [BVGAPI badgeForLine:a.line];
        v.layer.shadowColor = [UIColor blackColor].CGColor;
        v.layer.shadowOpacity = 0.25;
        v.layer.shadowRadius = 2;
        v.layer.shadowOffset = CGSizeMake(0, 1);
        v.layer.zPosition = 10;
    } else {
        v.image = [BVGAPI stopSignWithSize:18];
        v.layer.zPosition = 0;
    }
    return v;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    BVGAnnotation *a = (BVGAnnotation *)view.annotation;
    if (![a isKindOfClass:[BVGAnnotation class]]) return;

    if (a.kind == BVGAnnotationKindVehicle) {
        TripViewController *trip = [[TripViewController alloc] initWithTripId:a.identifier];
        trip.line = a.line;
        [self.navigationController pushViewController:trip animated:YES];
    } else {
        StopViewController *stop = [[StopViewController alloc] initWithStopId:a.identifier name:a.title];
        [self.navigationController pushViewController:stop animated:YES];
    }
}

@end
