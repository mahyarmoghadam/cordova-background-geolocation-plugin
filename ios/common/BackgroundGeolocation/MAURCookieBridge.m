//
//  MAURCookieBridge.m
//  BackgroundGeolocation
//

#import "MAURCookieBridge.h"
#import <WebKit/WebKit.h>

static BOOL domainMatchesHost(NSString *domain, NSString *host)
{
    if (domain == nil || host == nil) {
        return NO;
    }

    NSString *normalizedDomain = domain;
    if ([normalizedDomain hasPrefix:@"."]) {
        normalizedDomain = [normalizedDomain substringFromIndex:1];
    }

    if ([host isEqualToString:normalizedDomain]) {
        return YES;
    }

    return [host hasSuffix:[NSString stringWithFormat:@".%@", normalizedDomain]];
}

static BOOL pathMatchesURLPath(NSString *cookiePath, NSString *urlPath)
{
    if (cookiePath == nil || cookiePath.length == 0) {
        return YES;
    }
    if (urlPath == nil || urlPath.length == 0) {
        urlPath = @"/";
    }

    if ([urlPath hasPrefix:cookiePath]) {
        return YES;
    }

    // Handle common case where cookie path is "/".
    return [cookiePath isEqualToString:@"/"];
}

static BOOL cookieMatchesURL(NSHTTPCookie *cookie, NSURL *url)
{
    if (cookie == nil || url == nil) {
        return NO;
    }

    NSString *host = url.host;
    if (!domainMatchesHost(cookie.domain, host)) {
        return NO;
    }

    if (!pathMatchesURLPath(cookie.path, url.path)) {
        return NO;
    }

    if (cookie.isSecure && ![url.scheme.lowercaseString isEqualToString:@"https"]) {
        return NO;
    }

    return YES;
}

@implementation MAURCookieBridge

+ (void)applyCookiesToRequest:(NSMutableURLRequest * _Nonnull)request
        useWebViewCookieStore:(BOOL)useWebViewCookieStore
                      timeout:(NSTimeInterval)timeout
{
    if (!useWebViewCookieStore || request == nil || request.URL == nil) {
        return;
    }

    // Respect explicit Cookie header supplied via httpHeaders
    if ([request valueForHTTPHeaderField:@"Cookie"] != nil) {
        return;
    }

    NSURL *url = request.URL;
    NSMutableArray<NSHTTPCookie *> *matched = [NSMutableArray array];

    // Try to pull cookies from WKWebView cookie store (iOS 11+)
    if (@available(iOS 11.0, *)) {
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block NSArray<NSHTTPCookie *> *allCookies = nil;

        WKHTTPCookieStore *cookieStore = WKWebsiteDataStore.defaultDataStore.httpCookieStore;
        [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            allCookies = cookies;
            dispatch_semaphore_signal(sema);
        }];

        NSTimeInterval effectiveTimeout = ([NSThread isMainThread] ? 0 : timeout);
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(effectiveTimeout * NSEC_PER_SEC)));

        for (NSHTTPCookie *cookie in allCookies) {
            if (cookieMatchesURL(cookie, url)) {
                [matched addObject:cookie];
                [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
            }
        }
    }

    if (matched.count == 0) {
        NSArray<NSHTTPCookie *> *storageCookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url];
        if (storageCookies != nil) {
            [matched addObjectsFromArray:storageCookies];
        }
    }

    if (matched.count == 0) {
        return;
    }

    NSDictionary<NSString *, NSString *> *headerFields = [NSHTTPCookie requestHeaderFieldsWithCookies:matched];
    NSString *cookieHeader = headerFields[@"Cookie"];
    if (cookieHeader != nil && cookieHeader.length > 0) {
        [request setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
    }
}

+ (void)persistCookiesFromResponse:(NSHTTPURLResponse * _Nullable)response
                             forURL:(NSURL * _Nonnull)url
              useWebViewCookieStore:(BOOL)useWebViewCookieStore
{
    if (!useWebViewCookieStore || response == nil || url == nil) {
        return;
    }

    NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:response.allHeaderFields forURL:url];
    if (cookies == nil || cookies.count == 0) {
        return;
    }

    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in cookies) {
        [storage setCookie:cookie];
    }

    if (@available(iOS 11.0, *)) {
        WKHTTPCookieStore *cookieStore = WKWebsiteDataStore.defaultDataStore.httpCookieStore;
        for (NSHTTPCookie *cookie in cookies) {
            [cookieStore setCookie:cookie completionHandler:^{}];
        }
    }
}

@end
