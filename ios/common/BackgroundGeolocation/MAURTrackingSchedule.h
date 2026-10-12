//
//  MAURTrackingSchedule.h
//  BackgroundGeolocation
//
#import <Foundation/Foundation.h>

/**
 * Absolute tracking windows [start, end) in epoch ms, persisted in NSUserDefaults.
 * Never set = unrestricted; empty array = tracking blocked.
 */
@interface MAURTrackingSchedule : NSObject
+ (void) saveWindows:(NSArray<NSDictionary*>*)windows;
+ (BOOL) isAllowedAt:(NSDate*)date;
+ (NSDate*) currentWindowEndAt:(NSDate*)date;
+ (NSDate*) nextWindowStartAfter:(NSDate*)date;
@end
