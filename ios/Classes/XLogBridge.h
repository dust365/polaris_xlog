#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C facade over the C++ mars-xlog appender API so that the
/// Swift plugin can stay pure Swift. Implementation lives in XLogBridge.mm.
@interface XLogBridge : NSObject

+ (void)openWithLevel:(int)level
        consoleLogOpen:(BOOL)consoleLogOpen
                logDir:(NSString *)logDir
              cacheDir:(NSString *)cacheDir
            namePrefix:(NSString *)namePrefix
             cacheDays:(int)cacheDays
                pubKey:(NSString *)pubKey;

+ (void)setLevel:(int)level;
+ (void)logWithLevel:(int)level tag:(NSString *)tag message:(NSString *)message;
+ (void)flushSync:(BOOL)sync;
+ (void)close;

NS_ASSUME_NONNULL_END

@end
