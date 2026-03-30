//
//  MAURCookieBridge.m
//  BackgroundGeolocation
//

#import "MAURCookieBridge.h"
#import <WebKit/WebKit.h>

static void runOnMainThreadAsync(dispatch_block_t block)
{
    if (block == nil) {
        return;
    }

    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static NSString *cookieIdentityKey(NSHTTPCookie *cookie)
{
    if (cookie == nil) {
        return nil;
    }

    return [NSString stringWithFormat:@"%@|%@|%@",
            cookie.name ?: @"",
            cookie.domain ?: @"",
            cookie.path ?: @"/"];
}

static NSArray<NSHTTPCookie *> *mergeCookies(NSArray<NSHTTPCookie *> *first,
                                             NSArray<NSHTTPCookie *> *second)
{
    NSMutableDictionary<NSString *, NSHTTPCookie *> *uniqueCookies = [NSMutableDictionary dictionary];

    for (NSHTTPCookie *cookie in first) {
        NSString *key = cookieIdentityKey(cookie);
        if (key != nil) {
            uniqueCookies[key] = cookie;
        }
    }

    for (NSHTTPCookie *cookie in second) {
        NSString *key = cookieIdentityKey(cookie);
        if (key != nil) {
            uniqueCookies[key] = cookie;
        }
    }

    return [uniqueCookies allValues];
}

@implementation MAURCookieBridge

+ (void)applyCookiesToRequest:(NSMutableURLRequest * _Nonnull)request
        useWebViewCookieStore:(BOOL)useWebViewCookieStore
                   completion:(dispatch_block_t _Nullable)completion
{
    if (!useWebViewCookieStore || request == nil || request.URL == nil) {
        if (completion != nil) {
            completion();
        }
        return;
    }

    // Respect explicit Cookie header supplied via httpHeaders
    if ([request valueForHTTPHeaderField:@"Cookie"] != nil) {
        if (completion != nil) {
            completion();
        }
        return;
    }

    NSURL *url = request.URL;
    void (^finalizeRequest)(void) = ^{
        NSArray<NSHTTPCookie *> *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url];
        if (cookies.count > 0) {
            NSDictionary<NSString *, NSString *> *headerFields = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
            NSString *cookieHeader = headerFields[@"Cookie"];
            if (cookieHeader != nil && cookieHeader.length > 0) {
                [request setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
            }
        }

        if (completion != nil) {
            completion();
        }
    };

    if (@available(iOS 11.0, *)) {
        runOnMainThreadAsync(^{
            WKHTTPCookieStore *cookieStore = WKWebsiteDataStore.defaultDataStore.httpCookieStore;
            [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
                NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
                for (NSHTTPCookie *cookie in cookies) {
                    [storage setCookie:cookie];
                }

                finalizeRequest();
            }];
        });
    } else {
        finalizeRequest();
    }
}

+ (void)persistCookiesFromResponse:(NSHTTPURLResponse * _Nullable)response
                             forURL:(NSURL * _Nonnull)url
              useWebViewCookieStore:(BOOL)useWebViewCookieStore
                         completion:(dispatch_block_t _Nullable)completion
{
    if (!useWebViewCookieStore || response == nil || url == nil) {
        if (completion != nil) {
            completion();
        }
        return;
    }

    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray<NSHTTPCookie *> *responseCookies = [NSHTTPCookie cookiesWithResponseHeaderFields:response.allHeaderFields forURL:url];
    for (NSHTTPCookie *cookie in responseCookies) {
        [storage setCookie:cookie];
    }

    NSArray<NSHTTPCookie *> *cookiesToMirror = mergeCookies(responseCookies, [storage cookiesForURL:url]);
    if (cookiesToMirror.count == 0) {
        if (completion != nil) {
            completion();
        }
        return;
    }

    if (@available(iOS 11.0, *)) {
        runOnMainThreadAsync(^{
            WKHTTPCookieStore *cookieStore = WKWebsiteDataStore.defaultDataStore.httpCookieStore;
            dispatch_group_t group = dispatch_group_create();

            for (NSHTTPCookie *cookie in cookiesToMirror) {
                dispatch_group_enter(group);
                [cookieStore setCookie:cookie completionHandler:^{
                    dispatch_group_leave(group);
                }];
            }

            dispatch_group_notify(group, dispatch_get_main_queue(), ^{
                if (completion != nil) {
                    completion();
                }
            });
        });
    } else if (completion != nil) {
        completion();
    }
}

@end
