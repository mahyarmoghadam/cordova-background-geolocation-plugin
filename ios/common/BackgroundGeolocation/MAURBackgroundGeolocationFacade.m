//
//  MAURBackgroundGeolocationFacade.m
//
//  Created by Marian Hello on 04/06/16.
//  Version 2.0.0
//
//  According to apache license
//
//  This is class is using code from christocracy cordova-plugin-background-geolocation plugin
//  https://github.com/christocracy/cordova-plugin-background-geolocation
//

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "MAURBackgroundGeolocationFacade.h"
#import "MAURPostLocationTask.h"
#import "MAURSQLiteConfigurationDAO.h"
#import "MAURSQLiteLocationDAO.h"
#import "MAURBackgroundTaskManager.h"
#import "MAURLogging.h"
#import "FMDBLogger.h"
#import "MAURLogReader.h"
#import "MAURLocationManager.h"
#import "MAURActivityLocationProvider.h"
#import "MAURDistanceFilterLocationProvider.h"
#import "MAURRawLocationProvider.h"
#import "MAURUncaughtExceptionLogger.h"
#import "MAURPostLocationTask.h"
#import "INTULocationManager.h"
#import "MAURTrackingSchedule.h"

// error messages
#define CONFIGURE_ERROR_MSG             "Configuration error."
#define SERVICE_ERROR_MSG               "Cannot start service error."
#define UNKNOWN_LOCATION_PROVIDER_MSG   "Unknown location provider."

// Position errors
// https://developer.mozilla.org/en-US/docs/Web/API/PositionError
#define PERMISSION_DENIED       1
#define POSITION_UNAVAILABLE    2
#define TIMEOUT                 3

static NSString * const BGGeolocationDomain = @"com.marianhello";
static NSString * const TAG = @"BgGeo";

FMDBLogger *sqliteLogger;

@interface MAURBackgroundGeolocationFacade () <MAURProviderDelegate, MAURPostLocationTaskDelegate, CLLocationManagerDelegate>
- (void) enterStandbyStoppingProvider:(BOOL)stopProvider notify:(BOOL)notify;
- (void) leaveStandby;
- (void) stopStandbyMonitoring;
- (void) scheduleTimerForDate:(NSDate*)fireDate;
- (void) onScheduleTimer:(NSTimer*)timer;
- (BOOL) dropIfOutsideTrackingWindow;
- (void) runOnMainThread:(dispatch_block_t)completionHandle;
@end

@implementation MAURBackgroundGeolocationFacade {
    BOOL isStarted;
    // Schedule standby: armed (isStarted == YES) but outside a tracking window.
    // Only standbyManager (significant-change monitoring) runs; its locations are discarded.
    BOOL isStandby;
    CLLocationManager *standbyManager;
    NSTimer *scheduleTimer; // window end (tracking) or next window start (standby)
    NSDate *lastResumeFailure;
    MAUROperationalMode operationMode;
    
    UILocalNotification *localNotification;
    
    // configurable options
    MAURConfig *_config;
    
    MAURLocation *stationaryLocation;
    MAURAbstractLocationProvider<MAURLocationProvider> *locationProvider;
    MAURPostLocationTask *postLocationTask;
}


- (instancetype) init
{
    self = [super init];
    
    if (self == nil) {
        return self;
    }
    
    [DDLog addLogger:[DDASLLogger sharedInstance] withLevel:DDLogLevelInfo];
    [DDLog addLogger:[DDTTYLogger sharedInstance] withLevel:DDLogLevelDebug];
    
    sqliteLogger = [[FMDBLogger alloc] initWithLogDirectory:[self loggerDirectory]];
    sqliteLogger.saveThreshold     = 1;
    sqliteLogger.saveInterval      = 0;
    sqliteLogger.maxAge            = 60 * 60 * 24 * 7; //  7 days
    sqliteLogger.deleteInterval    = 60 * 60 * 24;     //  1 day
    sqliteLogger.deleteOnEverySave = NO;
    
    [DDLog addLogger:sqliteLogger withLevel:DDLogLevelDebug];
    
    MAHUncaughtExceptionLogger *logger = mah_get_uncaught_exception_logger();
    logger->setEnabled(YES);
    
    postLocationTask = [[MAURPostLocationTask alloc] init];
    postLocationTask.delegate = self;
    
    localNotification = [[UILocalNotification alloc] init];
    localNotification.timeZone = [NSTimeZone defaultTimeZone];
    
    isStarted = NO;
    isStandby = NO;

    return self;
}

/**
 * configure manager
 * @param {Config} configuration
 * @param {NSError} optional error
 */
- (BOOL) configure:(MAURConfig*)config error:(NSError * __autoreleasing *)outError
{
    __block NSError *error = nil;
    
    MAURConfig *currentConfig = [self getConfig];
    _config = [MAURConfig merge:currentConfig withConfig:config];
    
    DDLogInfo(@"%@ #configure: %@", TAG, _config);
    
    postLocationTask.config = _config;
    
    MAURSQLiteConfigurationDAO* configDAO = [MAURSQLiteConfigurationDAO sharedInstance];
    [configDAO persistConfiguration:_config];
    
    // ios 8 requires permissions to send local-notifications
    if ([_config isDebugging]) {
        [self runOnMainThread:^{
            UIApplication *app = [UIApplication sharedApplication];
            if ([[UIApplication sharedApplication]respondsToSelector:@selector(currentUserNotificationSettings)]) {
                UIUserNotificationType wantedTypes = UIUserNotificationTypeBadge|UIUserNotificationTypeSound|UIUserNotificationTypeAlert;
                UIUserNotificationSettings *currentSettings = [app currentUserNotificationSettings];
                if (!currentSettings || (currentSettings.types != wantedTypes)) {
                    if ([app respondsToSelector:@selector(registerUserNotificationSettings:)]) {
                        [app registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:wantedTypes categories:nil]];
                    }
                }
            }
        }];
    }
    
    // In schedule standby the provider stays off; the new config is applied when the next window starts.
    if (isStarted && !isStandby) {
        // Note: CLLocationManager must be created on a thread with an active run loop (main thread)
        [self runOnMainThread:^{

            // requesting new provider
            if (![currentConfig.locationProvider isEqual:_config.locationProvider]) {
                [locationProvider onDestroy]; // destroy current provider
                locationProvider = [self getProvider:_config.locationProvider.intValue error:&error];
            }
            
            if (locationProvider == nil) {
                return;
            }
            
            // trap configuration errors
            if (![locationProvider onConfigure:_config error:&error]) {
                return;
            }
            
            isStarted = [locationProvider onStart:&error];
            locationProvider.delegate = self;
        }];
    }
    
    if (error != nil) {
        if (outError != nil) {
            NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: NSLocalizedString(@CONFIGURE_ERROR_MSG, nil),
                                       NSUnderlyingErrorKey : error
                                       };
            *outError = [NSError errorWithDomain:BGGeolocationDomain code:MAURBGConfigureError userInfo:userInfo];
        }
        
        return NO;
    }
    
    return YES;
}

/**
 * Turn on background geolocation
 * in case of failure it calls error callback from configure method
 * may fire two callback when location services are disabled and when authorization failed
 */
- (BOOL) start:(NSError * __autoreleasing *)outError
{
    DDLogInfo(@"%@ #start: %d", TAG, isStarted);
    
    if (isStarted) {
        return NO;
    }

    if (![MAURTrackingSchedule isAllowedAt:[NSDate date]]) {
        isStarted = YES; // armed; real tracking starts at the next window
        [self enterStandbyStoppingProvider:NO notify:YES];
        return YES;
    }

    __block NSError *error = nil;
    MAURConfig *config = [self getConfig];
    
    postLocationTask.config = config;
    [postLocationTask start];
    
    // Note: CLLocationManager must be created on a thread with an active run loop (main thread)
    [self runOnMainThread:^{
        locationProvider = [self getProvider:config.locationProvider.intValue error:&error];
        
        if (locationProvider == nil) {
            return;
        }
        
        // trap configuration errors
        if (![locationProvider onConfigure:config error:&error]) {
            return;
        }
        
        isStarted = [locationProvider onStart:&error];
        locationProvider.delegate = self;
    }];
    
    
    if (!isStarted) {
        if (outError != nil) {
            *outError = error;
        }
        
        return NO;
    }

    [self scheduleTimerForDate:[MAURTrackingSchedule currentWindowEndAt:[NSDate date]]];

    return isStarted;
}

/**
 * Turn off background geolocation
 */
- (BOOL) stop:(NSError * __autoreleasing *)outError
{
    DDLogInfo(@"%@ #stop", TAG);

    [self stopStandbyMonitoring];
    BOOL wasStandby = isStandby;
    isStandby = NO;

    if (!isStarted) {
        return YES;
    }

    if (wasStandby) {
        // Provider and uploads are already stopped in standby.
        isStarted = NO;
        return isStarted; // same return convention as the regular path below
    }

    [postLocationTask stop];
    
    [self runOnMainThread:^{
        isStarted = ![locationProvider onStop:outError];
    }];
    
    return isStarted;
}

/**
 * toggle between foreground and background operation mode
 */
- (void) switchMode:(MAUROperationalMode)mode
{
    DDLogInfo(@"%@ #switchMode %lu", TAG, (unsigned long)mode);
    
    operationMode = mode;
    
    if (!isStarted) return;

    // App foreground/background transitions are a cheap moment to re-apply the schedule
    // (e.g. a window started or ended while the app was suspended).
    [self evaluateSchedule];
    if (isStandby || !isStarted) return; // provider is off in standby

    if ([self getConfig].isDebugging) {
        AudioServicesPlaySystemSound (operationMode  == MAURForegroundMode ? paceChangeYesSound : paceChangeNoSound);
    }
    
    [self runOnMainThread:^{
        [locationProvider onSwitchMode:mode];
    }];
}

- (BOOL) locationServicesEnabled
{
    if ([CLLocationManager respondsToSelector:@selector(locationServicesEnabled)]) { // iOS 4.x
        return [CLLocationManager locationServicesEnabled];
    }
    
    return NO;
}

- (MAURLocationAuthorizationStatus) authorizationStatus
{
    CLAuthorizationStatus authStatus = [CLLocationManager authorizationStatus];
    switch (authStatus) {
        case kCLAuthorizationStatusNotDetermined:
            return MAURLocationAuthorizationNotDetermined;
        case kCLAuthorizationStatusRestricted:
        case kCLAuthorizationStatusDenied:
            return MAURLocationAuthorizationDenied;
        case kCLAuthorizationStatusAuthorizedAlways:
            return MAURLocationAuthorizationAlways;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            return MAURLocationAuthorizationForeground;
    }
}

- (BOOL) isStarted
{
    return isStarted;
}

#pragma mark - Tracking schedule standby

- (BOOL) isStandby
{
    return isStandby;
}

- (void) evaluateSchedule
{
    // Serialize all standby transitions on the main thread (timer, CLLocationManager
    // callbacks and the provider all live there). runOnMainThread executes inline when
    // already on main and uses dispatch_sync otherwise, so this cannot self-deadlock.
    [self runOnMainThread:^{
        if (!isStarted) {
            return;
        }
        BOOL allowed = [MAURTrackingSchedule isAllowedAt:[NSDate date]];
        if (allowed && isStandby) {
            [self leaveStandby];
        } else if (!allowed && !isStandby) {
            [self enterStandbyStoppingProvider:YES notify:YES];
        } else if (allowed) {
            [self scheduleTimerForDate:[MAURTrackingSchedule currentWindowEndAt:[NSDate date]]];
        } else {
            // still in standby: refresh the next-start timer (windows may have changed)
            [self scheduleTimerForDate:[MAURTrackingSchedule nextWindowStartAfter:[NSDate date]]];
        }
    }];
}

/**
 * Stops real tracking and uploads, drops the offline queue and arms low-power
 * significant-change monitoring that only re-evaluates the schedule.
 */
- (void) enterStandbyStoppingProvider:(BOOL)stopProvider notify:(BOOL)notify
{
    DDLogInfo(@"%@ #enterStandby", TAG);
    BOOL providerRunning = stopProvider && !isStandby && locationProvider != nil;
    isStandby = YES;
    [postLocationTask stop];
    // Spec: nothing recorded in or before a window may be uploaded later from the offline queue.
    [[MAURSQLiteLocationDAO sharedInstance] deleteAllLocations:nil];

    NSDate *nextStart = [MAURTrackingSchedule nextWindowStartAfter:[NSDate date]];
    [self runOnMainThread:^{
        if (providerRunning) {
            [locationProvider onStop:nil];
        }
        if (standbyManager == nil) {
            standbyManager = [[CLLocationManager alloc] init];
            standbyManager.delegate = self;
        }
        // Low-power wake-ups only; locations delivered here are never stored or posted.
        [standbyManager startMonitoringSignificantLocationChanges];
    }];
    // Resumes on time while the app is alive; when suspended, the next
    // significant-change wake-up (or app start) applies the schedule instead.
    [self scheduleTimerForDate:nextStart];

    if (notify && self.delegate && [self.delegate respondsToSelector:@selector(onTrackingStandbyChanged:)]) {
        [self.delegate onTrackingStandbyChanged:YES];
    }
}

- (void) leaveStandby
{
    DDLogInfo(@"%@ #leaveStandby", TAG);
    [self stopStandbyMonitoring];
    isStandby = NO;
    isStarted = NO; // run the regular start path
    NSError *error = nil;
    BOOL started = [self start:&error];
    if (!started || !isStarted) {
        // Keep the schedule armed (mirrors Android): retry on the next wake-up.
        DDLogError(@"%@ leaveStandby start failed: %@", TAG, error);
        lastResumeFailure = [NSDate date];
        isStarted = YES;
        [self enterStandbyStoppingProvider:NO notify:NO];
        return;
    }
    lastResumeFailure = nil;
    if (isStandby) {
        // start: found the window already over and re-entered standby itself.
        return;
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(onTrackingStandbyChanged:)]) {
        [self.delegate onTrackingStandbyChanged:NO];
    }
}

- (void) stopStandbyMonitoring
{
    [self runOnMainThread:^{
        [scheduleTimer invalidate];
        scheduleTimer = nil;
        [standbyManager stopMonitoringSignificantLocationChanges];
    }];
}

/** (Re)arms the single schedule timer; nil date just cancels it. */
- (void) scheduleTimerForDate:(NSDate*)fireDate
{
    [self runOnMainThread:^{
        [scheduleTimer invalidate];
        scheduleTimer = nil;
        if (fireDate == nil) {
            return;
        }
        scheduleTimer = [[NSTimer alloc] initWithFireDate:fireDate
                                                 interval:0
                                                   target:self
                                                 selector:@selector(onScheduleTimer:)
                                                 userInfo:nil
                                                  repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:scheduleTimer forMode:NSRunLoopCommonModes];
    }];
}

- (void) onScheduleTimer:(NSTimer*)timer
{
    [self evaluateSchedule];
}

/**
 * Late-callback guard for provider locations. Returns YES (drop: never stored, posted or
 * emitted to JS) only outside a tracking window; inside a window it returns NO and the
 * location is processed normally. Standby is entered asynchronously (never from inside the
 * provider's own CLLocationManager callback) and only while the facade is started.
 */
- (BOOL) dropIfOutsideTrackingWindow
{
    if ([MAURTrackingSchedule isAllowedAt:[NSDate date]]) {
        return NO;
    }
    DDLogInfo(@"%@ dropping location outside tracking window", TAG);
    if (isStarted && !isStandby) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self evaluateSchedule];
        });
    }
    return YES;
}

#pragma mark - CLLocationManagerDelegate (standby manager only)

- (void) locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    if (manager != standbyManager) {
        return;
    }
    // Starting significant-change monitoring delivers an initial fix right away; after a failed
    // resume this would retry immediately in a loop, so retries from this path are throttled.
    if (lastResumeFailure != nil && [[NSDate date] timeIntervalSinceDate:lastResumeFailure] < 60.0) {
        return;
    }
    // Location is discarded; the wake-up is only used to re-apply the schedule.
    [self evaluateSchedule];
}

- (void) locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    if (manager == standbyManager) {
        DDLogWarn(@"%@ standby manager error: %@", TAG, error);
    }
}

- (MAURAbstractLocationProvider<MAURLocationProvider>*) getProvider:(int)providerId error:(NSError * __autoreleasing *)outError
{
    NSDictionary *errorDictionary;
    MAURAbstractLocationProvider<MAURLocationProvider> *locationProvider = nil;
    switch (providerId) {
        case DISTANCE_FILTER_PROVIDER:
            locationProvider = [[MAURDistanceFilterLocationProvider alloc] init];
            break;
        case ACTIVITY_PROVIDER:
            locationProvider = [[MAURActivityLocationProvider alloc] init];
            break;
        case RAW_PROVIDER:
            locationProvider = [[MAURRawLocationProvider alloc] init];
            break;
        default:
            if (outError != nil) {
                errorDictionary = @{
                                    NSLocalizedDescriptionKey: NSLocalizedString(@UNKNOWN_LOCATION_PROVIDER_MSG, nil),
                                    };
                *outError = [NSError errorWithDomain:BGGeolocationDomain code:MAURBGConfigureError userInfo:errorDictionary];
            }
            return nil;
    }
    [locationProvider onCreate];
    return locationProvider;
}

- (void) showAppSettings
{
    [self runOnMainThread:^{
        BOOL canGoToSettings = (UIApplicationOpenSettingsURLString != NULL);
        if (canGoToSettings) {
            NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            [[UIApplication sharedApplication] openURL:settingsURL 
                                               options:@{} 
                                     completionHandler:nil];
        }
    }];
}

- (void) showLocationSettings
{
    // NOOP - Since Apple started rejecting apps using non public url schemes
    // https://github.com/mauron85/cordova-plugin-background-geolocation/issues/394
}

- (MAURLocation*) getStationaryLocation
{
    return stationaryLocation;
}

- (NSArray<MAURLocation*>*) getLocations
{
    MAURSQLiteLocationDAO* locationDAO = [MAURSQLiteLocationDAO sharedInstance];
    return [locationDAO getAllLocations];
}

- (NSArray<MAURLocation*>*) getValidLocations
{
    MAURSQLiteLocationDAO* locationDAO = [MAURSQLiteLocationDAO sharedInstance];
    return [locationDAO getValidLocations];
}

- (NSArray<MAURLocation*>*) getValidLocationsAndDelete
{
    MAURSQLiteLocationDAO* locationDAO = [MAURSQLiteLocationDAO sharedInstance];
    return [locationDAO getLocationsForSync];
}

- (BOOL) deleteLocation:(NSNumber*)locationId error:(NSError * __autoreleasing *)outError
{
    MAURSQLiteLocationDAO* locationDAO = [MAURSQLiteLocationDAO sharedInstance];
    return [locationDAO deleteLocation:locationId error:outError];
}

- (BOOL) deleteAllLocations:(NSError * __autoreleasing *)outError
{
    MAURSQLiteLocationDAO* locationDAO = [MAURSQLiteLocationDAO sharedInstance];
    return [locationDAO deleteAllLocations:outError];
}

- (MAURLocation*)getCurrentLocation:(int)timeout maximumAge:(long)maximumAge
                 enableHighAccuracy:(BOOL)enableHighAccuracy
                              error:(NSError * __autoreleasing *)outError
{
    __block NSError *error = nil;
    __block CLLocation *location = nil;
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [self runOnMainThread:^{
        CLLocation *currentLocation = [MAURLocationManager sharedInstance].locationManager.location;
        if (currentLocation != nil) {
            long locationAge = ceil(fabs([currentLocation.timestamp timeIntervalSinceNow]) * 1000);
            if (locationAge <= maximumAge) {
                location = currentLocation;
                dispatch_semaphore_signal(sema);
                return;
            }
        }

        INTULocationManager *locationManager = [INTULocationManager sharedInstance];
        float timeoutInSeconds = ceil((float)timeout/1000);
        [locationManager requestLocationWithDesiredAccuracy:enableHighAccuracy ? INTULocationAccuracyRoom : INTULocationAccuracyCity
                                                    timeout:timeoutInSeconds
                                       delayUntilAuthorized:YES    // This parameter is optional, defaults to NO if omitted
                                                      block:^(CLLocation *currentLocation, INTULocationAccuracy achievedAccuracy, INTULocationStatus status) {
                                                          if (status == INTULocationStatusSuccess) {
                                                              // Request succeeded, meaning achievedAccuracy is at least the requested accuracy, and
                                                              // currentLocation contains the device's current location.
                                                              location = currentLocation;
                                                          }
                                                          else if (status == INTULocationStatusTimedOut) {
                                                              // Wasn't able to locate the user with the requested accuracy within the timeout interval.
                                                              // However, currentLocation contains the best location available (if any) as of right now,
                                                              // and achievedAccuracy has info on the accuracy/recency of the location in currentLocation.
                                                              error = [NSError errorWithDomain:BGGeolocationDomain code:TIMEOUT userInfo:nil];
                                                          }
                                                          else {
                                                              // An error occurred, more info is available by looking at the specific status returned.
                                                              error = [NSError errorWithDomain:BGGeolocationDomain code:POSITION_UNAVAILABLE userInfo:nil];
                                                          }
                                                          dispatch_semaphore_signal(sema);
                                                      }];
    }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    if (location != nil) {
        return [MAURLocation fromCLLocation:location];
    }

    if (outError != nil) {
        *outError = error;
    }

    return nil;
}

- (MAURConfig*) getConfig
{
    if (_config == nil) {
        MAURSQLiteConfigurationDAO* configDAO = [MAURSQLiteConfigurationDAO sharedInstance];
        _config = [configDAO retrieveConfiguration];
        if (_config == nil) {
            _config = [[MAURConfig alloc] initWithDefaults];
        }
    }
    
    return _config;
}

- (NSArray*) getLogEntries:(NSInteger)limit
{
    MAURLogReader *logReader = [[MAURLogReader alloc] initWithLogDirectory:[self loggerDirectory]];
    return [logReader getEntries:limit fromLogEntryId:0 minLogLevel:DDLogFlagDebug];
}

- (NSArray*) getLogEntries:(NSInteger)limit fromLogEntryId:(NSInteger)entryId minLogLevelFromString:(NSString *)minLogLevel
{
    MAURLogReader *logReader = [[MAURLogReader alloc] initWithLogDirectory:[self loggerDirectory]];
    return [logReader getLogEntries:limit fromLogEntryId:entryId minLogLevelAsString:minLogLevel];
}

- (NSArray*) getLogEntries:(NSInteger)limit fromLogEntryId:(NSInteger)entryId minLogLevel:(DDLogFlag)minLogLevel
{
    MAURLogReader *logReader = [[MAURLogReader alloc] initWithLogDirectory:[self loggerDirectory]];
    NSArray *logs = [logReader getEntries:limit fromLogEntryId:entryId minLogLevel:minLogLevel];
    return logs;
}

- (void) forceSync
{
    [postLocationTask sync];
}

- (void) notify:(NSString*)message
{
    localNotification.fireDate = [NSDate date];
    localNotification.alertBody = message;
    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
}

-(void) runOnMainThread:(dispatch_block_t)completionHandle {
    BOOL alreadyOnMainThread = [NSThread isMainThread];
    // this check avoids possible deadlock resulting from
    // calling dispatch_sync() on the same queue as current one
    if (alreadyOnMainThread) {
        // execute code in place
        completionHandle();
    } else {
        // dispatch to main queue
        dispatch_sync(dispatch_get_main_queue(), completionHandle);
    }
}

- (NSString *)loggerDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    
    return [basePath stringByAppendingPathComponent:@"SQLiteLogger"];
}

- (void) onStationaryChanged:(MAURLocation *)location
{
    DDLogDebug(@"%@ #onStationaryChanged", TAG);
    if ([self dropIfOutsideTrackingWindow]) {
        return;
    }
    stationaryLocation = location;
    
    [postLocationTask add:location];
    
    MAURConfig *config = [self getConfig];
    if ([config isDebugging]) {
        double distanceFilter = [MAURLocationManager sharedInstance].distanceFilter;
        [self notify:[NSString stringWithFormat:@"Stationary update: %s\nSPD: %0.0f | DF: %f | ACY: %0.0f | RAD: %0.0f",
                      ((operationMode == MAURForegroundMode) ? "FG" : "BG"),
                      [location.speed doubleValue],
                      distanceFilter,
                      [location.accuracy doubleValue],
                      [location.radius doubleValue]
                      ]];
        
        AudioServicesPlaySystemSound (locationSyncSound);
    }
    
    // Any javascript stationaryRegion event-listeners?
    if (self.delegate && [self.delegate respondsToSelector:@selector(onStationaryChanged:)]) {
        [self.delegate onStationaryChanged:location];
    }
}

- (void) onLocationChanged:(MAURLocation *)location
{
    DDLogDebug(@"%@ #onLocationChanged %@", TAG, location);
    if ([self dropIfOutsideTrackingWindow]) {
        return;
    }
    stationaryLocation = nil;
    
    [postLocationTask add:location];
    
    MAURConfig *config = [self getConfig];
    if ([config isDebugging]) {
        double distanceFilter = [MAURLocationManager sharedInstance].distanceFilter;
        [self notify:[NSString stringWithFormat:@"Location update: %s\nSPD: %0.0f | DF: %f | ACY: %0.0f",
                      ((operationMode == MAURForegroundMode) ? "FG" : "BG"),
                      [location.speed doubleValue],
                      distanceFilter,
                      [location.accuracy doubleValue]
                      ]];
        
        AudioServicesPlaySystemSound (locationSyncSound);
    }
    
    // Delegate to main module
    if (self.delegate && [self.delegate respondsToSelector:@selector(onLocationChanged:)]) {
        [self.delegate onLocationChanged:location];
    }
}

- (void) onAuthorizationChanged:(MAURLocationAuthorizationStatus)authStatus
{
    [self.delegate onAuthorizationChanged:authStatus];
}

- (void) onError:(NSError*)error
{
    [self.delegate onError:error];
}

- (void) onLocationPause
{
    [self.delegate onLocationPause];
}

- (void) onLocationResume
{
    [self.delegate onLocationResume];
}

- (void) onActivityChanged:(MAURActivity *)activity
{
    DDLogDebug(@"%@ #onActivityChanged %@", TAG, activity);
    
    if ([self getConfig].isDebugging) {
        [self notify:[NSString stringWithFormat:@"%@ activity detected: %@ activity, confidence: %@", TAG, activity.type, activity.confidence]];
    }
    
    [self.delegate onActivityChanged:activity];
}

/**@
 * If you don't stopMonitoring when application terminates, the app will be awoken still when a
 * new location arrives, essentially monitoring the user's location even when they've killed the app.
 * Might be desirable in certain apps.
 */
- (void) onAppTerminate
{
    MAURConfig *config = [self getConfig];
    if ([config stopOnTerminate]) {
        DDLogInfo(@"%@ #onAppTerminate.", TAG);
        [self stop:nil];
    } else {
        [locationProvider onTerminate];
    }
}

- (void) dealloc
{
    DDLogDebug(@"%@ #dealloc", TAG);
    // currently noop
}

#pragma mark - Location transform

+ (void) setLocationTransform:(MAURLocationTransform _Nullable)transform
{
    [MAURPostLocationTask setLocationTransform:transform];
}

+ (MAURLocationTransform _Nullable) locationTransform
{
    return [MAURPostLocationTask locationTransform];
}

#pragma mark - MAURPostLocationTaskDelegate

- (void) postLocationTaskRequestedAbortUpdates:(MAURPostLocationTask *)task
{
    if (_delegate && [_delegate respondsToSelector:@selector(onAbortRequested)])
    {
        // We have a delegate, tell it that there's a request.
        // It will decide whether to stop or not.
        [_delegate onAbortRequested];
    }
    else
    {
        // No delegate, we may be running in the background.
        // Let's just stop.
        [self stop:nil];
    }
}

- (void) postLocationTaskHttpAuthorizationUpdates:(MAURPostLocationTask *)task
{
    if (_delegate && [_delegate respondsToSelector:@selector(onHttpAuthorization)])
    {
        [_delegate onHttpAuthorization];
    }
}

@end
