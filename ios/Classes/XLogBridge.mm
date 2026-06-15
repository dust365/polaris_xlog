#import "XLogBridge.h"
#import <sys/time.h>
#import <pthread.h>

// mars-xlog C++ headers. Paths assume the mars pod / vendored framework
// exposes its headers under <mars/xlog/...>. Adjust if your build differs.
#import <mars/xlog/xlogger.h>
#import <mars/xlog/appender.h>

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

+ (void)setLevel:(int)level {
    xlogger_SetLevel((TLogLevel)level);
}

+ (void)logWithLevel:(int)level tag:(NSString *)tag message:(NSString *)message {
    XLoggerInfo info;
    memset(&info, 0, sizeof(XLoggerInfo));
    info.level = (TLogLevel)level;
    info.tag = tag.UTF8String;
    info.filename = "";
    info.func_name = "";
    info.line = 0;
    gettimeofday(&info.timeval, NULL);
    info.pid = getpid();
    info.tid = (uintptr_t)pthread_self();
    info.maintid = (uintptr_t)pthread_self();
    xlogger_Write(&info, message.UTF8String);
}

+ (void)flushSync:(BOOL)sync {
    if (sync) {
        appender_flush_sync();
    } else {
        appender_flush();
    }
}

+ (void)close {
    appender_close();
}

@end
