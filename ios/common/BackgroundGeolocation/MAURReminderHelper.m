//
//  MAURReminderHelper.m
//  BackgroundGeolocation
//

#import "MAURReminderHelper.h"
#import <UIKit/UIKit.h>
#import "MAURConfig.h"

NSString * const MAURReminderCategoryIdentifier = @"maur_bg_still_tracking_reminder";
NSString * const MAURReminderRequestIdentifier = @"maur_bg_still_tracking_reminder_request";
NSString * const MAURReminderActionStopIdentifier = @"maur_bg_still_tracking_reminder_stop";
NSString * const MAURReminderActionSnoozeIdentifier = @"maur_bg_still_tracking_reminder_snooze";
NSString * const MAURReminderActionMuteIdentifier = @"maur_bg_still_tracking_reminder_mute";

@interface MAURReminderHelper ()

@property (nonatomic, strong) UILocalNotification *legacyReminder;

@end

@implementation MAURReminderHelper

+ (instancetype)sharedInstance
{
    static MAURReminderHelper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)scheduleReminderWithConfig:(MAURConfig *)config
{
    NSTimeInterval interval = [self resolveIntervalSecondsFromMinutes:config.stillTrackingReminderIntervalMinutes fallback:nil];
    if (interval <= 0) {
        [self cancelReminder];
        return;
    }

    if (@available(iOS 10.0, *)) {
        [self requestAuthorizationIfNeededWithCompletion:^(BOOL granted) {
            if (!granted) {
                return;
            }
            [self ensureNotificationCategoriesWithConfig:config];
            [self scheduleReminderRequestWithConfig:config interval:interval];
        }];
    } else {
        [self scheduleLegacyReminderWithConfig:config interval:interval];
    }
}

- (void)scheduleSnoozeWithConfig:(MAURConfig *)config
{
    NSTimeInterval interval = [self resolveIntervalSecondsFromMinutes:config.stillTrackingReminderSnoozeIntervalMinutes fallback:config.stillTrackingReminderIntervalMinutes];
    if (interval <= 0) {
        [self cancelReminder];
        return;
    }

    if (@available(iOS 10.0, *)) {
        [self requestAuthorizationIfNeededWithCompletion:^(BOOL granted) {
            if (!granted) {
                return;
            }
            [self ensureNotificationCategoriesWithConfig:config];
            [self scheduleReminderRequestWithConfig:config interval:interval];
        }];
    } else {
        [self scheduleLegacyReminderWithConfig:config interval:interval];
    }
}

- (void)cancelReminder
{
    if (@available(iOS 10.0, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center removePendingNotificationRequestsWithIdentifiers:@[MAURReminderRequestIdentifier]];
        [center removeDeliveredNotificationsWithIdentifiers:@[MAURReminderRequestIdentifier]];
    }

    if (self.legacyReminder != nil) {
        [[UIApplication sharedApplication] cancelLocalNotification:self.legacyReminder];
        self.legacyReminder = nil;
    }
}

- (void)isReminderScheduledWithCompletion:(void (^)(BOOL scheduled))completion
{
    if (completion == nil) {
        return;
    }

    if (@available(iOS 10.0, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> * _Nonnull requests) {
            BOOL scheduled = NO;
            for (UNNotificationRequest *request in requests) {
                if ([request.identifier isEqualToString:MAURReminderRequestIdentifier]) {
                    scheduled = YES;
                    break;
                }
            }
            completion(scheduled);
        }];
    } else {
        completion(self.legacyReminder != nil);
    }
}

- (void)ensureNotificationCategoriesWithConfig:(MAURConfig *)config
{
    if (@available(iOS 10.0, *)) {
        UNNotificationAction *stopAction = [UNNotificationAction actionWithIdentifier:MAURReminderActionStopIdentifier title:[self reminderStopLabelFromConfig:config] options:UNNotificationActionOptionForeground];
        UNNotificationAction *snoozeAction = [UNNotificationAction actionWithIdentifier:MAURReminderActionSnoozeIdentifier title:[self reminderSnoozeLabelFromConfig:config] options:UNNotificationActionOptionNone];
        UNNotificationAction *muteAction = [UNNotificationAction actionWithIdentifier:MAURReminderActionMuteIdentifier title:[self reminderMuteLabelFromConfig:config] options:UNNotificationActionOptionNone];

        NSSet *identifiers = [NSSet set];
        UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:MAURReminderCategoryIdentifier actions:@[stopAction, snoozeAction, muteAction] intentIdentifiers:[identifiers allObjects] options:UNNotificationCategoryOptionCustomDismissAction];

        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center getNotificationCategoriesWithCompletionHandler:^(NSSet<UNNotificationCategory *> * _Nonnull categories) {
            NSMutableSet<UNNotificationCategory *> *mutable = [categories mutableCopy];
            if (mutable == nil) {
                mutable = [[NSMutableSet alloc] init];
            }
            [mutable addObject:category];
            [center setNotificationCategories:mutable];
        }];
    }
}

- (BOOL)isReminderNotificationResponse:(UNNotificationResponse *)response
{
    if (@available(iOS 10.0, *)) {
        NSString *identifier = response.notification.request.identifier;
        if ([identifier isEqualToString:MAURReminderRequestIdentifier]) {
            return YES;
        }
        if ([response.notification.request.content.categoryIdentifier isEqualToString:MAURReminderCategoryIdentifier]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isStopActionIdentifier:(NSString *)identifier
{
    return [identifier isEqualToString:MAURReminderActionStopIdentifier];
}

- (BOOL)isSnoozeActionIdentifier:(NSString *)identifier
{
    return [identifier isEqualToString:MAURReminderActionSnoozeIdentifier];
}

- (BOOL)isMuteActionIdentifier:(NSString *)identifier
{
    return [identifier isEqualToString:MAURReminderActionMuteIdentifier];
}

#pragma mark - Helpers

- (NSTimeInterval)resolveIntervalSecondsFromMinutes:(NSNumber *)minutes fallback:(NSNumber *)fallbackMinutes
{
    NSNumber *value = minutes != nil ? minutes : fallbackMinutes;
    if (value == nil) {
        return 0;
    }

    double interval = [value doubleValue] * 60.0;
    return interval > 0 ? interval : 0;
}

- (NSString *)reminderTitleFromConfig:(MAURConfig *)config
{
    if (config.stillTrackingReminderTitle != nil && ![config.stillTrackingReminderTitle isEqualToString:@""]) {
        return config.stillTrackingReminderTitle;
    }
    return @"Tracking is still running";
}

- (NSString *)reminderTextFromConfig:(MAURConfig *)config
{
    if (config.stillTrackingReminderText != nil && ![config.stillTrackingReminderText isEqualToString:@""]) {
        return config.stillTrackingReminderText;
    }
    return @"Background tracking remains active.";
}

- (NSString *)reminderStopLabelFromConfig:(MAURConfig *)config
{
    if (config.stillTrackingReminderStopLabel != nil && ![config.stillTrackingReminderStopLabel isEqualToString:@""]) {
        return config.stillTrackingReminderStopLabel;
    }
    return @"Stop";
}

- (NSString *)reminderSnoozeLabelFromConfig:(MAURConfig *)config
{
    if (config.stillTrackingReminderSnoozeLabel != nil && ![config.stillTrackingReminderSnoozeLabel isEqualToString:@""]) {
        return config.stillTrackingReminderSnoozeLabel;
    }
    return @"Snooze";
}

- (NSString *)reminderMuteLabelFromConfig:(MAURConfig *)config
{
    if (config.stillTrackingReminderMuteLabel != nil && ![config.stillTrackingReminderMuteLabel isEqualToString:@""]) {
        return config.stillTrackingReminderMuteLabel;
    }
    return @"Mute";
}

- (void)requestAuthorizationIfNeededWithCompletion:(void (^)(BOOL granted))completion
{
    if (@available(iOS 10.0, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
                [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError * _Nullable error) {
                    if (completion) {
                        completion(granted);
                    }
                }];
            } else {
                if (completion) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 120000
                    if (@available(iOS 12.0, *)) {
                        completion(settings.authorizationStatus == UNAuthorizationStatusAuthorized || settings.authorizationStatus == UNAuthorizationStatusProvisional);
                    } else {
                        completion(settings.authorizationStatus == UNAuthorizationStatusAuthorized);
                    }
#else
                    completion(settings.authorizationStatus == UNAuthorizationStatusAuthorized);
#endif
                }
            }
        }];
    } else {
        if (completion) {
            completion(YES);
        }
    }
}

- (void)scheduleReminderRequestWithConfig:(MAURConfig *)config interval:(NSTimeInterval)interval API_AVAILABLE(ios(10.0))
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [self reminderTitleFromConfig:config];
    content.body = [self reminderTextFromConfig:config];
    content.sound = [UNNotificationSound defaultSound];
    content.categoryIdentifier = MAURReminderCategoryIdentifier;

    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:interval repeats:NO];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:MAURReminderRequestIdentifier content:content trigger:trigger];

    [center removePendingNotificationRequestsWithIdentifiers:@[MAURReminderRequestIdentifier]];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"MAURReminderHelper: failed to schedule reminder: %@", error);
        }
    }];
}

- (void)scheduleLegacyReminderWithConfig:(MAURConfig *)config interval:(NSTimeInterval)interval
{
    UIApplication *application = [UIApplication sharedApplication];
    if (self.legacyReminder != nil) {
        [application cancelLocalNotification:self.legacyReminder];
    }

    UILocalNotification *notification = [[UILocalNotification alloc] init];
    notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:interval];
    if ([notification respondsToSelector:@selector(setAlertTitle:)]) {
        notification.alertTitle = [self reminderTitleFromConfig:config];
    }
    notification.alertBody = [self reminderTextFromConfig:config];
    notification.soundName = UILocalNotificationDefaultSoundName;

    self.legacyReminder = notification;
    [application scheduleLocalNotification:notification];
}

@end
