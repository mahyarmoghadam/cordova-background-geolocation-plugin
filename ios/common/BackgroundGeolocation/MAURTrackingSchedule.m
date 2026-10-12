//
//  MAURTrackingSchedule.m
//  BackgroundGeolocation
//
#import "MAURTrackingSchedule.h"

static NSString * const kWindowsKey = @"MAURTrackingWindows";

@implementation MAURTrackingSchedule

+ (void) saveWindows:(NSArray<NSDictionary*>*)windows
{
    NSMutableArray *valid = [NSMutableArray array];
    for (NSDictionary *w in windows ?: @[]) {
        if (![w isKindOfClass:[NSDictionary class]]) continue;
        NSNumber *start = w[@"start"];
        NSNumber *end = w[@"end"];
        if (![start isKindOfClass:[NSNumber class]] || ![end isKindOfClass:[NSNumber class]]) continue;
        if (end.longLongValue <= start.longLongValue) continue;
        [valid addObject:@[start, end]];
    }
    [valid sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSNumber *startA = (NSNumber *)((NSArray *)a)[0];
        NSNumber *startB = (NSNumber *)((NSArray *)b)[0];
        return [startA compare:startB];
    }];
    [[NSUserDefaults standardUserDefaults] setObject:valid forKey:kWindowsKey];
}

+ (NSArray<NSArray<NSNumber*>*>*) windows
{
    return [[NSUserDefaults standardUserDefaults] arrayForKey:kWindowsKey];
}

+ (long long) msFromDate:(NSDate*)date
{
    return (long long)([date timeIntervalSince1970] * 1000.0);
}

+ (BOOL) isAllowedAt:(NSDate*)date
{
    if ([self windows] == nil) {
        return YES; // never configured: unrestricted (backward compatible)
    }
    return [self currentWindowEndAt:date] != nil;
}

+ (NSDate*) currentWindowEndAt:(NSDate*)date
{
    long long now = [self msFromDate:date];
    for (NSArray<NSNumber*> *w in [self windows]) {
        if (now >= w[0].longLongValue && now < w[1].longLongValue) {
            return [NSDate dateWithTimeIntervalSince1970:w[1].doubleValue / 1000.0];
        }
    }
    return nil;
}

+ (NSDate*) nextWindowStartAfter:(NSDate*)date
{
    long long now = [self msFromDate:date];
    for (NSArray<NSNumber*> *w in [self windows]) {
        if (w[0].longLongValue > now) {
            return [NSDate dateWithTimeIntervalSince1970:w[0].doubleValue / 1000.0];
        }
    }
    return nil;
}

@end
