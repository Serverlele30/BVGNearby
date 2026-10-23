#import "TripMapViewController.h"
#import "BVGAnnotation.h"
#import "BVGAPI.h"
#import <MapKit/MapKit.h>

@interface TripMapViewController () <MKMapViewDelegate>
@property (nonatomic, copy) NSString *tripId;
@property (nonatomic, strong) NSDictionary *line;
@property (nonatomic, strong) MKMapView *map;
@property (nonatomic, strong) BVGAnnotation *vehicle;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL drawn;
@end

@implementation TripMapViewController

- (instancetype)initWithTripId:(NSString *)tripId line:(NSDictionary *)line {
    self = [super init];
    if (self) {
        _tripId = [tripId copy];
        _line = line;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = [NSString stringWithFormat:@"%@ live", NN(self.line[@"name"]) ?: @"Fahrt"];
    self.map = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.map.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.map.delegate = self;
    self.map.showsUserLocation = YES;
    self.map.showsPointsOfInterest = NO;
    [self.view addSubview:self.map];
    [self load];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(load) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)load {
    NSString *path = [NSString stringWithFormat:@"/trips/%@?stopovers=true&polyline=%@&remarks=false",
                      [BVGAPI encode:self.tripId], self.drawn ? @"false" : @"true"];
    [BVGAPI getJSON:path completion:^(id json, NSError *error) {
        NSDictionary *trip = [json isKindOfClass:[NSDictionary class]] ? NN(json[@"trip"]) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!trip) { NSLog(@"TripMap-Fehler: %@", error); return; }
            if (!self.drawn) [self drawRoute:trip];
            [self updateVehicle:trip];
        });
    }];
}

- (void)drawRoute:(NSDictionary *)trip {
    // Linienverlauf (GeoJSON FeatureCollection mit Punkten)
    NSDictionary *poly = NN(trip[@"polyline"]);
    NSArray *features = [poly isKindOfClass:[NSDictionary class]] ? NN(poly[@"features"]) : nil;
    NSMutableData *coords = [NSMutableData data];
    for (NSDictionary *f in features) {
        NSArray *c = NN(NN(f[@"geometry"])[@"coordinates"]);
        if (![c isKindOfClass:[NSArray class]] || c.count < 2) continue;
        CLLocationCoordinate2D p = CLLocationCoordinate2DMake([c[1] doubleValue], [c[0] doubleValue]);
        [coords appendBytes:&p length:sizeof(p)];
    }

    // Halte
    NSMutableArray *stopAnns = [NSMutableArray array];
    id stopovers = NN(trip[@"stopovers"]);
    if ([stopovers isKindOfClass:[NSArray class]]) {
        for (NSDictionary *so in stopovers) {
            NSDictionary *stop = NN(so[@"stop"]);
            NSDictionary *loc = NN(stop[@"location"]);
            if (![loc isKindOfClass:[NSDictionary class]]) continue;
            CLLocationCoordinate2D p = CLLocationCoordinate2DMake([loc[@"latitude"] doubleValue], [loc[@"longitude"] doubleValue]);

            BVGAnnotation *a = [[BVGAnnotation alloc] init];
            a.kind = BVGAnnotationKindTripStop;
            a.title = NN(stop[@"name"]) ?: @"?";
            NSDate *t = [BVGAPI dateFromISO:so[@"departure"]] ?: [BVGAPI dateFromISO:so[@"arrival"]];
            a.subtitle = t ? [BVGAPI hhmm:t] : nil;
            a.coordinate = p;
            [stopAnns addObject:a];

            // ohne Polyline: Halte direkt verbinden
            if (!features.count) [coords appendBytes:&p length:sizeof(p)];
        }
    }

    NSUInteger n = coords.length / sizeof(CLLocationCoordinate2D);
    if (n >= 2) {
        MKPolyline *line = [MKPolyline polylineWithCoordinates:(CLLocationCoordinate2D *)coords.bytes count:n];
        [self.map addOverlay:line];
        [self.map setVisibleMapRect:line.boundingMapRect edgePadding:UIEdgeInsetsMake(40, 30, 40, 30) animated:NO];
    }
    [self.map addAnnotations:stopAnns];
    self.drawn = YES;
}

- (void)updateVehicle:(NSDictionary *)trip {
    NSDictionary *loc = NN(trip[@"currentLocation"]);
    if (![loc isKindOfClass:[NSDictionary class]]) return;
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake([loc[@"latitude"] doubleValue], [loc[@"longitude"] doubleValue]);

    if (!self.vehicle) {
        self.vehicle = [[BVGAnnotation alloc] init];
        self.vehicle.kind = BVGAnnotationKindVehicle;
        self.vehicle.line = self.line;
        self.vehicle.title = [NSString stringWithFormat:@"%@ → %@", NN(self.line[@"name"]) ?: @"?", NN(trip[@"direction"]) ?: @""];
        self.vehicle.coordinate = c;
        [self.map addAnnotation:self.vehicle];
    } else {
        [UIView animateWithDuration:2.0 animations:^{ self.vehicle.coordinate = c; }];
    }
}

#pragma mark - MKMapViewDelegate

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
    r.strokeColor = [[BVGAPI colorForLine:self.line] colorWithAlphaComponent:0.85];
    r.lineWidth = 5;
    r.lineCap = kCGLineCapRound;
    r.lineJoin = kCGLineJoinRound;
    return r;
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if (![annotation isKindOfClass:[BVGAnnotation class]]) return nil;
    BVGAnnotation *a = (BVGAnnotation *)annotation;
    NSString *reuse = a.kind == BVGAnnotationKindVehicle ? @"veh" : @"halt";

    MKAnnotationView *v = [mapView dequeueReusableAnnotationViewWithIdentifier:reuse];
    if (!v) {
        v = [[MKAnnotationView alloc] initWithAnnotation:a reuseIdentifier:reuse];
        v.canShowCallout = YES;
    }
    v.annotation = a;
    if (a.kind == BVGAnnotationKindVehicle) {
        v.image = [BVGAPI badgeForLine:a.line];
        v.layer.zPosition = 10;
        v.layer.shadowOpacity = 0.4;
        v.layer.shadowRadius = 2;
        v.layer.shadowOffset = CGSizeMake(0, 1);
    } else {
        v.image = [BVGAPI dotWithColor:[BVGAPI colorForLine:self.line] filled:NO];
    }
    return v;
}

@end
