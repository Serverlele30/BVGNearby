#import "BVGSettings.h"

NSString * const BVGSettingsChangedNotification = @"BVGSettingsChanged";

@implementation BVGSettings

+ (void)initialize {
    if (self != [BVGSettings class]) return;
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"set.radius": @1000,
        @"set.perStop": @5,
        @"set.transfer": @5,
        @"set.boardLead": @2,
        @"set.speech": @YES,
        @"set.ownServer": @YES,
    }];
}

+ (NSInteger)radius            { return [[NSUserDefaults standardUserDefaults] integerForKey:@"set.radius"]; }
+ (NSInteger)departuresPerStop { return [[NSUserDefaults standardUserDefaults] integerForKey:@"set.perStop"]; }
+ (NSInteger)transferMinutes   { return MAX(5, [[NSUserDefaults standardUserDefaults] integerForKey:@"set.transfer"]); }
+ (NSInteger)boardLeadMinutes  { return [[NSUserDefaults standardUserDefaults] integerForKey:@"set.boardLead"]; }
+ (BOOL)speechEnabled          { return [[NSUserDefaults standardUserDefaults] boolForKey:@"set.speech"]; }
+ (BOOL)useOwnServer           { return [[NSUserDefaults standardUserDefaults] boolForKey:@"set.ownServer"]; }

+ (NSDictionary *)placeForKey:(NSString *)key {
    NSDictionary *p = [[NSUserDefaults standardUserDefaults] dictionaryForKey:[@"place." stringByAppendingString:key]];
    return p[@"name"] ? p : nil;
}

+ (void)setPlace:(NSDictionary *)place forKey:(NSString *)key {
    NSString *k = [@"place." stringByAppendingString:key];
    if (place) [[NSUserDefaults standardUserDefaults] setObject:place forKey:k];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:k];
    [[NSNotificationCenter defaultCenter] postNotificationName:BVGSettingsChangedNotification object:nil];
}

+ (NSString *)directionFilterForStop:(NSString *)stopId {
    if (!stopId) return nil;
    return [[NSUserDefaults standardUserDefaults] stringForKey:[@"dir." stringByAppendingString:stopId]];
}

+ (void)setDirectionFilter:(NSString *)direction forStop:(NSString *)stopId {
    if (!stopId) return;
    NSString *k = [@"dir." stringByAppendingString:stopId];
    if (direction) [[NSUserDefaults standardUserDefaults] setObject:direction forKey:k];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:k];
    [[NSNotificationCenter defaultCenter] postNotificationName:BVGSettingsChangedNotification object:nil];
}

+ (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:BVGSettingsChangedNotification object:nil];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:BVGSettingsChangedNotification object:nil];
}

@end
