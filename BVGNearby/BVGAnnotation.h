#import <MapKit/MapKit.h>

typedef NS_ENUM(NSInteger, BVGAnnotationKind) {
    BVGAnnotationKindStop,
    BVGAnnotationKindVehicle,
    BVGAnnotationKindTripStop
};

@interface BVGAnnotation : NSObject <MKAnnotation>
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;   // KVO-faehig -> animierbar
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, assign) BVGAnnotationKind kind;
@property (nonatomic, copy) NSString *identifier;     // stopId oder tripId
@property (nonatomic, strong) NSDictionary *line;
@end
