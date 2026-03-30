//
//  MAURCookieBridge.h
//  BackgroundGeolocation
//

#ifndef MAURCookieBridge_h
#define MAURCookieBridge_h

#import <Foundation/Foundation.h>

@interface MAURCookieBridge : NSObject

+ (void)applyCookiesToRequest:(NSMutableURLRequest * _Nonnull)request
        useWebViewCookieStore:(BOOL)useWebViewCookieStore
                   completion:(dispatch_block_t _Nullable)completion;

+ (void)persistCookiesFromResponse:(NSHTTPURLResponse * _Nullable)response
                             forURL:(NSURL * _Nonnull)url
              useWebViewCookieStore:(BOOL)useWebViewCookieStore
                         completion:(dispatch_block_t _Nullable)completion;

@end

#endif /* MAURCookieBridge_h */
