#import "XLogBridge.h"
#import <CommonCrypto/CommonDigest.h>

// mars' comm/strutil.cc references OpenSSL's MD5(), but iOS ships no libcrypto.
// Provide a drop-in shim backed by CommonCrypto so the vendored framework links.
extern "C" unsigned char *MD5(const unsigned char *data, unsigned long len, unsigned char *md) {
    return CC_MD5(data, (CC_LONG)len, md);
}

// mars-xlog C++ headers from the vendored mars.xcframework (Headers/xlog/...).
// We deliberately include xloggerbase.h (the plain extern "C" API) instead of
// xlogger.h, because xlogger.h pulls "mars/comm/string_cast.h" via a relative
// include that doesn't resolve with the framework's Headers/{comm,xlog} layout.
#import <mars/xlog/appender.h>
#import <mars/xlog/xloggerbase.h>

using namespace mars::xlog;

@implementation XLogBridge

+ (void)openWithLevel:(int)level
        consoleLogOpen:(BOOL)consoleLogOpen
                logDir:(NSString *)logDir
              cacheDir:(NSString *)cacheDir
            namePrefix:(NSString *)namePrefix
             cacheDays:(int)cacheDays
                pubKey:(NSString *)pubKey {
    XLogConfig config;
    config.mode_ = kAppenderAsync;
    config.logdir_ = logDir.UTF8String;
    config.nameprefix_ = namePrefix.UTF8String;          // -> <prefix>_YYYYMMDD.xlog (one file/day)
    config.pub_key_ = pubKey.UTF8String;
    config.compress_mode_ = kZlib;
    config.compress_level_ = 0;
    config.cachedir_ = cacheDir.UTF8String;
    config.cache_days_ = cacheDays;
    appender_open(config);
    xlogger_SetLevel((TLogLevel)level);
    appender_set_console_log(consoleLogOpen);
}

@end
