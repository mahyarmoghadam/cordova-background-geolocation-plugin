//
//  CDVBackgroundGeolocation.h
//
//  Created by Marian Hello on 04/06/16.
//  Version 2.0.0
//
//  According to apache license
//
//  This is class is using code from christocracy cordova-plugin-background-geolocation plugin
//  https://github.com/christocracy/cordova-plugin-background-geolocation

#import "CDVBackgroundGeolocation.h"
#import "MAURConfig.h"
#import "MAURBackgroundGeolocationFacade.h"
#import "MAURBackgroundTaskManager.h"
#import "MAURReminderHelper.h"
#import "MAURSQLiteConfigurationDAO.h"

static NSString * const TAG = @"CDVBackgroundGeolocation";

@implementation CDVBackgroundGeolocation {
    NSString *callbackId;
    MAURConfig *config;
    MAURBackgroundGeolocationFacade* facade;
    MAURReminderHelper *reminderHelper;

    BOOL pendingReminderNotificationTap;
    NSDictionary *pendingReminderNotificationTapPayload;

    API_AVAILABLE(ios(10.0))
    __weak id<UNUserNotificationCenterDelegate> prevNotificationDelegate;
}

- (void)pluginInitialize
{

    facade = [[MAURBackgroundGeolocationFacade alloc] init];
    facade.delegate = self;
    reminderHelper = [MAURReminderHelper sharedInstance];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppPause:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppResume:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onFinishLaunching:) name:UIApplicationDidFinishLaunchingNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppTerminate:) name:UIApplicationWillTerminateNotification object:nil];
}

/**
 * configure plugin
 * @param {Number} stationaryRadius
 * @param {Number} distanceFilter
 * @param {Number} locationTimeout
 */
- (void) configure:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"configure");
    [self.commandDelegate runInBackground:^{
        config = [MAURConfig fromDictionary:[command.arguments objectAtIndex:0]];

        NSError *error = nil;
        CDVPluginResult* result = nil;
        BOOL configured = [facade configure:config error:&error];
        if (configured) {
            [self rescheduleReminderIfTracking];
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            [reminderHelper cancelReminder];
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self errorToDictionary:error]];
        }
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

/**
 * Turn on background geolocation
 * in case of failure it calls error callback from configure method
 * may fire two callback when location services are disabled and when authorization failed
 */
- (void) start:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"start");
    [self.commandDelegate runInBackground:^{
        NSError *error = nil;
        MAURConfig *startConfig = [self currentConfigInstance];
        if (startConfig == nil) {
            startConfig = [[MAURConfig alloc] initWithDefaults];
        }
        config = startConfig;

        [facade start:&error];
        if (error == nil) {
            [self sendEvent:@"start"];
        } else {
            [self sendError:error];
        }
        CDVPluginResult* result = nil;
        BOOL configured = [facade configure:config error:&error];
        if (configured) {
            [self rescheduleReminderIfTracking];
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            [reminderHelper cancelReminder];
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self errorToDictionary:error]];
        }
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

/**
 * Turn it off
 */
- (void) stop:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"stop");
    [self.commandDelegate runInBackground:^{
        NSError *error = nil;

        [facade stop:&error];
        if (error == nil) {
            [self sendEvent:@"stop"];
        } else {
            [self sendError:error];
        }
        [reminderHelper cancelReminder];
        CDVPluginResult* result = nil;
        if ([facade configure:config error:&error]) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self errorToDictionary:error]];
        }
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

/**
 * Snooze the still-tracking reminder if tracking is active and no reminder is already scheduled.
 */
- (void) snoozeReminder:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"snoozeReminder");
    [self.commandDelegate runInBackground:^{
        if (![facade isStarted]) {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            return;
        }

        MAURConfig *activeConfig = [self currentConfigInstance];
        if (activeConfig == nil) {
            activeConfig = [[MAURConfig alloc] initWithDefaults];
        }

        [self ensureNotificationDelegateIfNeeded];
        [reminderHelper isReminderScheduledWithCompletion:^(BOOL scheduled) {
            if (!scheduled) {
                [reminderHelper scheduleSnoozeWithConfig:activeConfig];
            }
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }];
    }];
}

/**
 * Change
 * @param {Number} operation mode BACKGROUND/FOREGROUND
 */
- (void) switchMode:(CDVInvokedUrlCommand *)command
{
    NSLog(@"%@ #%@", TAG, @"switchMode");
    [self.commandDelegate runInBackground:^{
        MAUROperationalMode mode = [[command.arguments objectAtIndex: 0] intValue];
        [facade switchMode:mode];
    }];
}

- (void) getConfig:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"getConfig");
    [self.commandDelegate runInBackground:^{
        MAURConfig *config = [facade getConfig];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[config toDictionary]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) checkStatus:(CDVInvokedUrlCommand *)command
{
    NSLog(@"%@ #%@", TAG, @"checkStatus");
    [self.commandDelegate runInBackground:^{
        BOOL isRunning = [facade isStarted];
        BOOL locationServicesEnabled = [facade locationServicesEnabled];
        NSInteger authorizationStatus = [facade authorizationStatus];

        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:3];
        [dict setObject:[NSNumber numberWithBool:isRunning] forKey:@"isRunning"];
        [dict setObject:[NSNumber numberWithBool:locationServicesEnabled] forKey:@"hasPermissions"]; // @deprecated
        [dict setObject:[NSNumber numberWithBool:locationServicesEnabled] forKey:@"locationServicesEnabled"];
        [dict setObject:[NSNumber numberWithInteger:authorizationStatus] forKey:@"authorization"];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dict];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

/**
 * Fetches current stationaryLocation
 */
- (void) getStationaryLocation:(CDVInvokedUrlCommand *)command
{
    NSLog(@"%@ #%@", TAG, @"getStationaryLocation");
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* result = nil;

        MAURLocation* stationaryLocation = [facade getStationaryLocation];
        if (stationaryLocation) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[stationaryLocation toDictionary]];
        } else {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO];
        }

        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) isLocationEnabled:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"isLocationEnabled");
    [self.commandDelegate runInBackground:^{
        BOOL isLocationEnabled = [facade locationServicesEnabled];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:isLocationEnabled];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) showAppSettings:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"showAppSettings");
    [self.commandDelegate runInBackground:^{
        [facade showAppSettings];
    }];
}

- (void) showLocationSettings:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"showLocationSettings");
    [self.commandDelegate runInBackground:^{
        [facade showLocationSettings];
    }];
}

- (void) getLocations:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"getLocations");
    [self.commandDelegate runInBackground:^{
        NSArray *locations = [facade getLocations];
        NSMutableArray* dictionaryLocations = [[NSMutableArray alloc] initWithCapacity:[locations count]];
        for (MAURLocation* location in locations) {
            [dictionaryLocations addObject:[location toDictionaryWithId]];
        }
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:dictionaryLocations];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) getValidLocations:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"getValidLocations");
    [self.commandDelegate runInBackground:^{
        NSArray *locations = [facade getValidLocations];
        NSMutableArray* dictionaryLocations = [[NSMutableArray alloc] initWithCapacity:[locations count]];
        for (MAURLocation* location in locations) {
            [dictionaryLocations addObject:[location toDictionaryWithId]];
        }
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:dictionaryLocations];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) getValidLocationsAndDelete:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"getValidLocationsAndDelete");
    [self.commandDelegate runInBackground:^{
        NSArray *locations = [facade getValidLocationsAndDelete];
        NSMutableArray* dictionaryLocations = [[NSMutableArray alloc] initWithCapacity:[locations count]];
        for (MAURLocation* location in locations) {
            [dictionaryLocations addObject:[location toDictionaryWithId]];
        }
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:dictionaryLocations];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) deleteLocation:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"deleteLocation");
    [self.commandDelegate runInBackground:^{
        NSError *error = nil;
        int locationId = [[command.arguments objectAtIndex: 0] intValue];
        BOOL success = [facade deleteLocation:[[NSNumber alloc] initWithInt:locationId] error:&error];
        CDVPluginResult* result;
        if (success) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self errorToDictionary:error]];
        }
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) deleteAllLocations:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"deleteAllLocations");
    [self.commandDelegate runInBackground:^{
        NSError *error = nil;
        BOOL success = [facade deleteAllLocations:&error];
        CDVPluginResult* result;
        if (success) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self errorToDictionary:error]];
        }
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) getCurrentLocation:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"getCurrentLocation");
    [self.commandDelegate runInBackground:^{
        NSError *error = nil;
        NSArray *args = command.arguments;
        int timeout = [args objectAtIndex: 0] == [NSNull null] ? INT_MAX : [[args objectAtIndex: 0] intValue];
        long maximumAge = [args objectAtIndex: 1] == [NSNull null] ? LONG_MAX : [[args objectAtIndex: 1] longValue];
        BOOL enableHighAccuracy = [args objectAtIndex: 2] == [NSNull null] ? NO : [[args objectAtIndex: 2] boolValue];

        MAURLocation *location = [facade getCurrentLocation:timeout maximumAge:maximumAge enableHighAccuracy:enableHighAccuracy error:&error];
        CDVPluginResult* result;
        if (location != nil) {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[location toDictionary]];
        } else {
            result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self errorToDictionary:error]];
        }
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) getLogEntries:(CDVInvokedUrlCommand*)command
{
    NSLog(@"%@ #%@", TAG, @"getLogEntries");
    [self.commandDelegate runInBackground:^{
        NSArray *args = command.arguments;
        NSInteger limit = [args objectAtIndex: 0] == [NSNull null]
            ? 0 : [[args objectAtIndex: 0] integerValue];
        NSInteger entryId = [args objectAtIndex: 1] == [NSNull null]
            ? 0 : [[args objectAtIndex: 1] integerValue];
        NSString *minLogLevel = [args objectAtIndex: 2] == [NSNull null]
            ? @"DEBUG" : [args objectAtIndex: 2];

        NSArray *logs = [facade getLogEntries:limit fromLogEntryId:entryId minLogLevelFromString:minLogLevel];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:logs];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) startTask:(CDVInvokedUrlCommand*)command
{
    NSUInteger taskKey = [[MAURBackgroundTaskManager sharedTasks] beginTask];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsNSUInteger:taskKey];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void) endTask:(CDVInvokedUrlCommand*)command
{
    int taskKey = [[command.arguments objectAtIndex: 0] intValue];
    [[MAURBackgroundTaskManager sharedTasks] endTaskWithKey:taskKey];
}

- (void) forceSync:(CDVInvokedUrlCommand*)command
{
    [facade forceSync];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void) addEventListener:(CDVInvokedUrlCommand*)command
{
    callbackId = command.callbackId;
    [self flushPendingReminderNotificationTap];
}

- (void) removeEventListener:(CDVInvokedUrlCommand*)command
{
    callbackId = nil;
}

- (MAURConfig *)currentConfigInstance
{
    if (config != nil) {
        return config;
    }

    return [facade getConfig];
}

- (void)ensureNotificationDelegateIfNeeded
{
    if (@available(iOS 10, *)) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        if (center.delegate != self) {
            prevNotificationDelegate = center.delegate;
            center.delegate = self;
        }
    }
}

- (void)rescheduleReminderIfTracking
{
    if ([facade isStarted]) {
        MAURConfig *activeConfig = [self currentConfigInstance];
        if (activeConfig != nil) {
            [self ensureNotificationDelegateIfNeeded];
            [reminderHelper scheduleReminderWithConfig:activeConfig];
        }
    } else {
        [reminderHelper cancelReminder];
    }
}

-(void) sendEvent:(NSString*)name
{
    if (callbackId == nil) {
        return;
    }

    NSDictionary *message = [[NSDictionary alloc] initWithObjectsAndKeys:[NSString stringWithFormat:@"%@", name], @"name", nil];
    CDVPluginResult* cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
    [cordovaResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:cordovaResult callbackId:callbackId];
}

-(void) sendEvent:(NSString*)name resultAsNumber:(NSNumber*)result
{
    if (callbackId == nil) {
        return;
    }

    NSDictionary *message = [[NSDictionary alloc] initWithObjectsAndKeys:
                           [NSString stringWithFormat:@"%@", name], @"name",
                           result, @"payload",
                           nil];
    CDVPluginResult* cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
    [cordovaResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:cordovaResult callbackId:callbackId];
}

-(void) sendEvent:(NSString*)name result:(id)result
{
    if (callbackId == nil) {
        return;
    }

    NSDictionary *message = [[NSDictionary alloc] initWithObjectsAndKeys:
                           [NSString stringWithFormat:@"%@", name], @"name",
                           result, @"payload",
                           nil];
    CDVPluginResult* cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
    [cordovaResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:cordovaResult callbackId:callbackId];
}

- (void)dispatchReminderNotificationTap:(NSDictionary *)payload
{
    if (callbackId == nil) {
        pendingReminderNotificationTap = YES;
        pendingReminderNotificationTapPayload = payload;
        return;
    }

    [self sendEvent:@"reminder_notification_tap" result:payload];
}

- (void)flushPendingReminderNotificationTap
{
    if (!pendingReminderNotificationTap) {
        return;
    }
    pendingReminderNotificationTap = NO;

    NSDictionary *payload = pendingReminderNotificationTapPayload;
    pendingReminderNotificationTapPayload = nil;
    if (payload == nil) {
        payload = @{
            @"action": @"tap",
            @"notificationId": @2001,
            @"timestamp": @((long long)([[NSDate date] timeIntervalSince1970] * 1000.0))
        };
    }
    [self sendEvent:@"reminder_notification_tap" result:payload];
}

- (void) sendError:(NSError*)error
{
    NSLog(@"%@ #%@", TAG, @"onError");
    if (callbackId == nil) {
        return;
    }

    CDVPluginResult* cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self errorToDictionary:error]];
    [cordovaResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:cordovaResult callbackId:callbackId];
}

- (NSDictionary*) errorToDictionary:(NSError*)error
{
    NSDictionary *userInfo = [error userInfo];
    NSString *errorMessage = [error localizedDescription];
    if (errorMessage == nil) {
        errorMessage = [[userInfo objectForKey:NSUnderlyingErrorKey] localizedDescription];
    }
    return @{ @"code": [NSNumber numberWithLong:error.code], @"message": errorMessage};
}

- (void) onAuthorizationChanged:(MAURLocationAuthorizationStatus)authStatus
{
    NSLog(@"%@ #%@", TAG, @"onAuthorizationChanged");
    [self sendEvent:@"authorization" resultAsNumber:[NSNumber numberWithInt:authStatus]];
}

- (void) onLocationChanged:(MAURLocation*)location
{
    NSLog(@"%@ #%@", TAG, @"onLocationChanged");
    [self sendEvent:@"location" result:[location toDictionaryWithId]];
}

- (void) onStationaryChanged:(MAURLocation*)location
{
    NSLog(@"%@ #%@", TAG, @"onStationaryChanged");
    [self sendEvent:@"stationary" result:[location toDictionaryWithId]];
}

- (void) onLocationPause
{
    NSLog(@"%@ %@", TAG, @"location updates paused");
    [self sendEvent:@"stop"];
}

- (void) onLocationResume
{
    NSLog(@"%@ %@", TAG, @"location updates resumed");
    [self sendEvent:@"start"];
}

- (void) onActivityChanged:(MAURActivity *)activity
{
    NSLog(@"%@ #%@", TAG, @"onActivityChanged");
    [self sendEvent:@"activity" result:[activity toDictionary]];
}

- (void) onError:(NSError*)error
{
    NSLog(@"%@ #%@", TAG, @"onError");
    [self sendError:error];
}

-(void) onAppResume:(NSNotification *)notification
{
    NSLog(@"%@ %@", TAG, @"resumed");
    [facade switchMode:MAURForegroundMode];
}

-(void) onAppPause:(NSNotification *)notification
{
    NSLog(@"%@ %@", TAG, @"paused");
    [facade switchMode:MAURBackgroundMode];
}

-(void) onAbortRequested
{
    NSLog(@"%@ %@", TAG, @"abort requested by the server");
    [self sendEvent:@"abort_requested"];
}

- (void) onHttpAuthorization {
    NSLog(@"%@ %@", TAG, @"http authorization requested by the server");
    [self sendEvent:@"http_authorization"];
}

/**@
 * on UIApplicationDidFinishLaunchingNotification
 */
-(void) onFinishLaunching:(NSNotification *)notification
{
    NSDictionary *dict = [notification userInfo];
    MAURConfig *config = [facade getConfig];

    if (config.isDebugging)
    {
        if (@available(iOS 10, *))
        {
            UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
            prevNotificationDelegate = center.delegate;
            center.delegate = self;
        }
    }

    if ([dict objectForKey:UIApplicationLaunchOptionsLocationKey]) {
        NSLog(@"%@ %@", TAG, @"started by system on location event.");
        if (![config stopOnTerminate]) {
            MAURSQLiteConfigurationDAO *configDAO = [MAURSQLiteConfigurationDAO sharedInstance];
            [configDAO persistConfiguration:config];
            [facade start:nil];
            [facade switchMode:MAURBackgroundMode];
            [self ensureNotificationDelegateIfNeeded];
            [reminderHelper scheduleReminderWithConfig:config];
        }
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
    if (prevNotificationDelegate && [prevNotificationDelegate respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)])
    {
        // Give other delegates (like FCM) the chance to process this notification

        [prevNotificationDelegate userNotificationCenter:center willPresentNotification:notification withCompletionHandler:^(UNNotificationPresentationOptions options) {
            completionHandler(UNNotificationPresentationOptionAlert);
        }];
    }
    else
    {
        completionHandler(UNNotificationPresentationOptionAlert);
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler
{
    BOOL handled = NO;

    if ([reminderHelper isReminderNotificationResponse:response]) {
        handled = YES;
        NSString *actionIdentifier = response.actionIdentifier;
        MAURConfig *activeConfig = [self currentConfigInstance];
        if (activeConfig == nil) {
            activeConfig = [[MAURConfig alloc] initWithDefaults];
        }

        if ([reminderHelper isStopActionIdentifier:actionIdentifier]) {
            NSError *stopError = nil;
            [facade stop:&stopError];
            [reminderHelper cancelReminder];
            [self sendEvent:@"stop"];
        } else if (@available(iOS 10.0, *)) {
            if ([actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
                NSDictionary *payload = @{
                    @"action": @"tap",
                    @"notificationId": @2001,
                    @"timestamp": @((long long)([[NSDate date] timeIntervalSince1970] * 1000.0))
                };
                [self dispatchReminderNotificationTap:payload];
                [reminderHelper cancelReminder];
            } else if ([reminderHelper isSnoozeActionIdentifier:actionIdentifier]) {
                if ([facade isStarted]) {
                    [self ensureNotificationDelegateIfNeeded];
                    [reminderHelper scheduleSnoozeWithConfig:activeConfig];
                } else {
                    [reminderHelper cancelReminder];
                }
            } else if ([reminderHelper isMuteActionIdentifier:actionIdentifier]) {
                [reminderHelper cancelReminder];
            } else {
                [reminderHelper cancelReminder];
            }
        }
    }

    if (prevNotificationDelegate && [prevNotificationDelegate respondsToSelector:@selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)])
    {
        [prevNotificationDelegate userNotificationCenter:center didReceiveNotificationResponse:response withCompletionHandler:completionHandler];
        return;
    }

    if (completionHandler != nil) {
        completionHandler();
    }
    (void)handled;
}

-(void) onAppTerminate:(NSNotification *)notification
{
    NSLog(@"%@ %@", TAG, @"appTerminate");
    [facade onAppTerminate];
    [reminderHelper cancelReminder];
}

@end
