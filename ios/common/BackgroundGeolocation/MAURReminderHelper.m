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
NSString * const MAURReminderErrorDomain = @"com.marianhello.bgloc.reminder";

@interface MAURReminderHelper ()

@property (nonatomic, strong) UILocalNotification *legacyReminder;

- (NSTimeInterval)resolveReminderIntervalSecondsFromConfig:(MAURConfig *)config;
- (NSTimeInterval)resolveSnoozeIntervalSecondsFromConfig:(MAURConfig *)config;
- (NSTimeInterval)resolveIntervalSecondsFromMinutes:(NSNumber *)minutes;
- (void)requestAuthorizationIfNeededWithCompletion:(void (^)(BOOL granted, NSError *error))completion;
- (void)handleAuthorizationSettings:(UNNotificationSettings *)settings completion:(void (^)(BOOL granted, NSError *error))completion API_AVAILABLE(ios(10.0));
- (NSError *)reminderErrorWithCode:(MAURReminderErrorCode)code description:(NSString *)description;
- (void)scheduleReminderRequestWithConfig:(MAURConfig *)config interval:(NSTimeInterval)interval completion:(void (^)(BOOL scheduled, NSError *error))completion API_AVAILABLE(ios(10.0));
- (void)scheduleLegacyReminderWithConfig:(MAURConfig *)config interval:(NSTimeInterval)interval;

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
    [self scheduleReminderWithConfig:config completion:nil];
}

- (void)scheduleReminderWithConfig:(MAURConfig *)config completion:(void (^)(BOOL scheduled, NSError *error))completion
{
    NSTimeInterval interval = [self resolveReminderIntervalSecondsFromConfig:config];
    if (interval <= 0) {
        [self cancelReminder];
        if (completion != nil) {
            completion(NO, nil);
        }
        return;
    }

    if (@available(iOS 10.0, *)) {
        [self requestAuthorizationIfNeededWithCompletion:^(BOOL granted, NSError *error) {
            if (!granted) {
                if (completion != nil) {
                    completion(NO, error);
                }
                return;
            }
            [self ensureNotificationCategoriesWithConfig:config completion:^{
                [self scheduleReminderRequestWithConfig:config interval:interval completion:completion];
            }];
        }];
    } else {
        [self scheduleLegacyReminderWithConfig:config interval:interval];
        if (completion != nil) {
            completion(YES, nil);
        }
    }
}

- (void)scheduleSnoozeWithConfig:(MAURConfig *)config
{
    [self scheduleSnoozeWithConfig:config completion:nil];
}

- (void)scheduleSnoozeWithConfig:(MAURConfig *)config completion:(void (^)(BOOL scheduled, NSError *error))completion
{
    NSTimeInterval interval = [self resolveSnoozeIntervalSecondsFromConfig:config];
    if (interval <= 0) {
        [self cancelReminder];
        if (completion != nil) {
            completion(NO, nil);
        }
        return;
    }

    if (@available(iOS 10.0, *)) {
        [self requestAuthorizationIfNeededWithCompletion:^(BOOL granted, NSError *error) {
            if (!granted) {
                if (completion != nil) {
                    completion(NO, error);
                }
                return;
            }
            [self ensureNotificationCategoriesWithConfig:config completion:^{
                [self scheduleReminderRequestWithConfig:config interval:interval completion:completion];
            }];
        }];
    } else {
        [self scheduleLegacyReminderWithConfig:config interval:interval];
        if (completion != nil) {
            completion(YES, nil);
        }
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
    [self ensureNotificationCategoriesWithConfig:config completion:nil];
}

- (void)ensureNotificationCategoriesWithConfig:(MAURConfig *)config completion:(dispatch_block_t)completion
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
            for (UNNotificationCategory *existingCategory in categories) {
                if ([existingCategory.identifier isEqualToString:MAURReminderCategoryIdentifier]) {
                    [mutable removeObject:existingCategory];
                }
            }
            [mutable addObject:category];
            [center setNotificationCategories:mutable];
            if (completion != nil) {
                completion();
            }
        }];
    } else if (completion != nil) {
        completion();
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

- (NSTimeInterval)resolveReminderIntervalSecondsFromConfig:(MAURConfig *)config
{
    return [self resolveIntervalSecondsFromMinutes:config.stillTrackingReminderIntervalMinutes];
}

- (NSTimeInterval)resolveSnoozeIntervalSecondsFromConfig:(MAURConfig *)config
{
    if (config.stillTrackingReminderSnoozeIntervalMinutes != nil) {
        return [self resolveIntervalSecondsFromMinutes:config.stillTrackingReminderSnoozeIntervalMinutes];
    }

    if (config.stillTrackingReminderIntervalMinutes == nil) {
        return 0;
    }

    NSInteger reminderIntervalMinutes = [config.stillTrackingReminderIntervalMinutes integerValue];
    if (reminderIntervalMinutes <= 0) {
        return 0;
    }

    NSInteger derivedSnoozeMinutes = MAX((NSInteger)1, (reminderIntervalMinutes + 3) / 4);
    return [self resolveIntervalSecondsFromMinutes:@(derivedSnoozeMinutes)];
}

- (NSTimeInterval)resolveIntervalSecondsFromMinutes:(NSNumber *)minutes
{
    NSNumber *value = minutes;
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

- (void)requestAuthorizationIfNeededWithCompletion:(void (^)(BOOL granted, NSError *error))completion
{
    if (@available(iOS 10.0, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
                [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError * _Nullable error) {
                    if (error != nil) {
                        NSLog(@"MAURReminderHelper: notification authorization request failed: %@", error);
                        if (completion != nil) {
                            completion(NO, error);
                        }
                        return;
                    }
                    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull updatedSettings) {
                        [self handleAuthorizationSettings:updatedSettings completion:completion];
                    }];
                }];
            } else {
                [self handleAuthorizationSettings:settings completion:completion];
            }
        }];
    } else {
        if (completion != nil) {
            completion(YES, nil);
        }
    }
}

- (void)handleAuthorizationSettings:(UNNotificationSettings *)settings completion:(void (^)(BOOL granted, NSError *error))completion API_AVAILABLE(ios(10.0))
{
    if (completion == nil) {
        return;
    }

    BOOL isAuthorized = settings.authorizationStatus == UNAuthorizationStatusAuthorized;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 120000
    if (@available(iOS 12.0, *)) {
        isAuthorized = isAuthorized || settings.authorizationStatus == UNAuthorizationStatusProvisional;
    }
#endif

    if (!isAuthorized) {
        NSString *message = @"Reminder notification permission was denied on iOS; skipping reminder schedule.";
        NSLog(@"MAURReminderHelper: %@", message);
        completion(NO, [self reminderErrorWithCode:MAURReminderErrorCodePermissionDenied description:message]);
        return;
    }

    if (settings.alertSetting != UNNotificationSettingEnabled && settings.alertSetting != UNNotificationSettingNotSupported) {
        NSString *message = @"Reminder notification alerts are disabled on iOS; reminder would not be visible.";
        NSLog(@"MAURReminderHelper: %@", message);
        completion(NO, [self reminderErrorWithCode:MAURReminderErrorCodeAlertsDisabled description:message]);
        return;
    }

    completion(YES, nil);
}

- (NSError *)reminderErrorWithCode:(MAURReminderErrorCode)code description:(NSString *)description
{
    return [NSError errorWithDomain:MAURReminderErrorDomain code:code userInfo:@{
        NSLocalizedDescriptionKey: description
    }];
}

- (void)scheduleReminderRequestWithConfig:(MAURConfig *)config interval:(NSTimeInterval)interval completion:(void (^)(BOOL scheduled, NSError *error))completion API_AVAILABLE(ios(10.0))
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
            if (completion != nil) {
                NSString *message = [NSString stringWithFormat:@"Failed to schedule iOS reminder notification: %@", error.localizedDescription];
                completion(NO, [self reminderErrorWithCode:MAURReminderErrorCodeScheduleFailed description:message]);
            }
            return;
        }

        NSLog(@"MAURReminderHelper: scheduled reminder in %.0f seconds", interval);
        if (completion != nil) {
            completion(YES, nil);
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
