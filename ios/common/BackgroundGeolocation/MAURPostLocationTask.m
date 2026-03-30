//
//  MAURPostLocationTask.m
//  BackgroundGeolocation
//
//  Created by Marian Hello on 27/04/2018.
//  Copyright © 2018 mauron85. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Reachability.h"
#import "MAURSQLiteLocationDAO.h"
#import "MAURBackgroundSync.h"
#import "MAURConfig.h"
#import "MAURLogging.h"
#import "MAURPostLocationTask.h"
#import "MAURSQLiteLocationDAO.h"
#import "MAURCookieBridge.h"

static NSString * const TAG = @"MAURPostLocationTask";

@interface MAURPostLocationTask() <MAURBackgroundSyncDelegate>
{
    
}

- (void)post:(MAURLocation*)location
       toUrl:(NSString*)url
withTemplate:(id)locationTemplate
withHttpHeaders:(NSMutableDictionary*)httpHeaders
  completion:(void (^ _Nonnull)(BOOL success))completion;
@end

@implementation MAURPostLocationTask
{
    Reachability *reach;
    MAURBackgroundSync *uploader;
    BOOL hasConnectivity;
}

static MAURLocationTransform s_locationTransform = nil;

- (instancetype) init
{
    self = [super init];

    if (self == nil) {
        return self;
    }

    hasConnectivity = YES;

    uploader = [[MAURBackgroundSync alloc] init];
    uploader.delegate = self;
    
    reach = [Reachability reachabilityWithHostname:@"www.google.com"];
    reach.reachableBlock = ^(Reachability *_reach) {
        // keep in mind this is called on a background thread
        // and if you are updating the UI it needs to happen
        // on the main thread:
        hasConnectivity = YES;
        [_reach stopNotifier];
    };
    
    reach.unreachableBlock = ^(Reachability *reach) {
        hasConnectivity = NO;
    };

    return self;
}

- (void) start
{
    hasConnectivity = YES;
    [reach startNotifier];
}

- (void) stop
{
    [reach stopNotifier];
}

- (void) add:(MAURLocation * _Nonnull)inLocation
{
    // Take this variable on the main thread to be safe
    MAURLocationTransform locationTransform = s_locationTransform;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        
        MAURLocation *location = inLocation;
        
        if (locationTransform != nil) {
            location = locationTransform(location);
            
            if (location == nil) {
                return;
            }
        }
        
        MAURSQLiteLocationDAO *locationDAO = [MAURSQLiteLocationDAO sharedInstance];
        // TODO: investigate location id always 0
        NSNumber *locationId = [locationDAO persistLocation:location limitRows:_config.maxLocations.integerValue];

        void (^finishAdd)(void) = ^{
            if ([self.config hasValidSyncUrl]) {
                NSNumber *locationsCount = [locationDAO getLocationsForSyncCount];
                if (locationsCount && [locationsCount integerValue] >= self.config.syncThreshold.integerValue) {
                    DDLogDebug(@"%@ Attempt to sync locations: %@ threshold: %@", TAG, locationsCount, self.config.syncThreshold);
                    [self sync];
                }
            }
        };
        
        if (hasConnectivity && [self.config hasValidUrl]) {
            [self post:location toUrl:self.config.url withTemplate:self.config._template withHttpHeaders:self.config.httpHeaders completion:^(BOOL success) {
                if (locationId != nil) {
                    if (success) {
                        [locationDAO deleteLocation:locationId error:nil];
                    }
                }
                finishAdd();
            }];
        } else {
            finishAdd();
        }
    });
}

- (void)post:(MAURLocation*)location
       toUrl:(NSString*)url
withTemplate:(id)locationTemplate
withHttpHeaders:(NSMutableDictionary*)httpHeaders
  completion:(void (^ _Nonnull)(BOOL success))completion
{
    NSArray *locations = [[NSArray alloc] initWithObjects:[location toResultFromTemplate:locationTemplate], nil];
    NSError *serializationError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:locations options:0 error:&serializationError];
    if (!data) {
        DDLogError(@"%@ Error while serializing location payload %@", TAG, [serializationError localizedDescription]);
        completion(NO);
        return;
    }
    
    NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPMethod:@"POST"];
    if (httpHeaders != nil) {
        for(id key in httpHeaders) {
            id value = [httpHeaders objectForKey:key];
            [request addValue:value forHTTPHeaderField:key];
        }
    }

    [MAURCookieBridge applyCookiesToRequest:request useWebViewCookieStore:self.config.useWebViewCookieStore completion:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [request setHTTPBody:[jsonStr dataUsingEncoding:NSUTF8StringEncoding]];

            NSError *requestError = nil;
            NSHTTPURLResponse* urlResponse = nil;
            [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&requestError];

            [MAURCookieBridge persistCookiesFromResponse:urlResponse forURL:request.URL useWebViewCookieStore:self.config.useWebViewCookieStore completion:^{
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    NSInteger statusCode = urlResponse.statusCode;

                    if (statusCode == 285)
                    {
                        DDLogDebug(@"Location was sent to the server, and received an \"HTTP 285 Updated Not Required\"");

                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (_delegate && [_delegate respondsToSelector:@selector(postLocationTaskRequestedAbortUpdates:)])
                            {
                                [_delegate postLocationTaskRequestedAbortUpdates:self];
                            }
                        });
                    }

                    if (statusCode == 401)
                    {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (_delegate && [_delegate respondsToSelector:@selector(postLocationTaskHttpAuthorizationUpdates:)])
                            {
                                [_delegate postLocationTaskHttpAuthorizationUpdates:self];
                            }
                        });
                    }

                    if (statusCode >= 200 && statusCode < 300)
                    {
                        completion(YES);
                        return;
                    }

                    if (requestError == nil) {
                        DDLogDebug(@"%@ Server error while posting locations responseCode: %ld", TAG, (long)statusCode);
                    } else {
                        DDLogError(@"%@ Error while posting locations %@", TAG, [requestError localizedDescription]);
                    }

                    completion(NO);
                });
            }];
        });
    }];
}

- (void) sync
{
    if ([self.config hasValidSyncUrl]) {
        [uploader sync:self.config.syncUrl withTemplate:self.config._template withHttpHeaders:self.config.httpHeaders useWebViewCookieStore:self.config.useWebViewCookieStore];
    }
}

#pragma mark - Location transform

+ (void) setLocationTransform:(MAURLocationTransform _Nullable)transform
{
    s_locationTransform = transform;
}

+ (MAURLocationTransform _Nullable) locationTransform
{
    return s_locationTransform;
}

#pragma mark - MAURBackgroundSyncDelegate

- (void)backgroundSyncRequestedAbortUpdates:(MAURBackgroundSync *)task
{
    if (_delegate && [_delegate respondsToSelector:@selector(postLocationTaskRequestedAbortUpdates:)])
    {
        [_delegate postLocationTaskRequestedAbortUpdates:self];
    }
}

- (void)backgroundSyncHttpAuthorizationUpdates:(MAURBackgroundSync *)task
{
    if (_delegate && [_delegate respondsToSelector:@selector(postLocationTaskHttpAuthorizationUpdates:)])
    {
        [_delegate postLocationTaskHttpAuthorizationUpdates:self];
    }
}

@end
