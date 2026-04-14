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
extern NSString * const MAURReminderErrorDomain;

typedef NS_ENUM(NSInteger, MAURReminderErrorCode) {
    MAURReminderErrorCodePermissionDenied = 2001,
    MAURReminderErrorCodeAlertsDisabled = 2002,
    MAURReminderErrorCodeScheduleFailed = 2003
};

@interface MAURReminderHelper : NSObject

+ (instancetype)sharedInstance;

- (void)scheduleReminderWithConfig:(MAURConfig *)config;
- (void)scheduleReminderWithConfig:(MAURConfig *)config completion:(void (^)(BOOL scheduled, NSError *error))completion;
- (void)scheduleSnoozeWithConfig:(MAURConfig *)config;
- (void)scheduleSnoozeWithConfig:(MAURConfig *)config completion:(void (^)(BOOL scheduled, NSError *error))completion;
- (void)cancelReminder;
- (void)isReminderScheduledWithCompletion:(void (^)(BOOL scheduled))completion;
- (void)ensureNotificationCategoriesWithConfig:(MAURConfig *)config;
- (void)ensureNotificationCategoriesWithConfig:(MAURConfig *)config completion:(dispatch_block_t)completion;
- (BOOL)isReminderNotificationResponse:(UNNotificationResponse *)response API_AVAILABLE(ios(10.0));
- (BOOL)isStopActionIdentifier:(NSString *)identifier;
- (BOOL)isSnoozeActionIdentifier:(NSString *)identifier;
- (BOOL)isMuteActionIdentifier:(NSString *)identifier;

@end
