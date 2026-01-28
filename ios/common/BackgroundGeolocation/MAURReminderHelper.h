//
//  MAURReminderHelper.h
//  BackgroundGeolocation
//
//  Helper for scheduling still-tracking reminder notifications.
//

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

@class MAURConfig;

extern NSString * const MAURReminderCategoryIdentifier;
extern NSString * const MAURReminderRequestIdentifier;
extern NSString * const MAURReminderActionStopIdentifier;
extern NSString * const MAURReminderActionSnoozeIdentifier;
extern NSString * const MAURReminderActionMuteIdentifier;

@interface MAURReminderHelper : NSObject

+ (instancetype)sharedInstance;

- (void)scheduleReminderWithConfig:(MAURConfig *)config;
- (void)scheduleSnoozeWithConfig:(MAURConfig *)config;
- (void)cancelReminder;
- (void)isReminderScheduledWithCompletion:(void (^)(BOOL scheduled))completion;
- (void)ensureNotificationCategoriesWithConfig:(MAURConfig *)config;
- (BOOL)isReminderNotificationResponse:(UNNotificationResponse *)response API_AVAILABLE(ios(10.0));
- (BOOL)isStopActionIdentifier:(NSString *)identifier;
- (BOOL)isSnoozeActionIdentifier:(NSString *)identifier;
- (BOOL)isMuteActionIdentifier:(NSString *)identifier;

@end
