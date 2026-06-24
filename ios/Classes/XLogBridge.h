#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C facade over the C++ mars-xlog appender API so that the
/// Swift plugin can open the appender from the `init` channel call (it needs the
/// app sandbox path). The hot path (log / setLevel / flush / close) does NOT go
/// through here — Dart calls the C shim in xlog_ffi.mm directly via dart:ffi.
/// Implementation lives in XLogBridge.mm.
@interface XLogBridge : NSObject

+ (void)openWithLevel:(int)level
        consoleLogOpen:(BOOL)consoleLogOpen
                logDir:(NSString *)logDir
              cacheDir:(NSString *)cacheDir
            namePrefix:(NSString *)namePrefix
             cacheDays:(int)cacheDays
                pubKey:(NSString *)pubKey;

NS_ASSUME_NONNULL_END

@end
