// xlog_ffi.mm — iOS FFI shim over mars-xlog.
//
// This is the iOS counterpart of native/src/xlog_ffi.cc (Android). The two
// files share the same tiny extern "C" surface (keep them in sync); they differ
// only in how the mars headers are included:
//   - Android: compiled into libxlog from the mars source tree ("appender.h").
//   - iOS:     compiled as a plugin Pod source, so it uses the framework header
//              layout (<mars/xlog/...>) just like XLogBridge.mm.
//
// Why the shim lives in the plugin Pod (and not inside mars.framework): the
// plugin's own polaris_xlog.framework is already a *dynamic* framework that
// CocoaPods always embeds, so symbols compiled into it are exported and reached
// by Dart's DynamicLibrary.process() — with no linker dead-strip (the object is
// compiled directly into the framework, marked used + default-visibility) and
// none of the embed/link-ordering problems of vendoring mars itself as dynamic.
// mars stays a static framework, linked into polaris_xlog.framework as in 0.1.0.
// See docs/ffi_0.2.0_plan.md §3.

#import <sys/time.h>
#import <CommonCrypto/CommonDigest.h>

#import <mars/xlog/appender.h>
#import <mars/xlog/xloggerbase.h>

// mars' comm/strutil.cc references OpenSSL's MD5(), but iOS ships no libcrypto.
// Provide a drop-in shim backed by CommonCrypto so the vendored mars static
// framework links. (Previously lived in XLogBridge.mm, which has been removed.)
extern "C" unsigned char *MD5(const unsigned char *data, unsigned long len, unsigned char *md) {
    return CC_MD5(data, (CC_LONG)len, md);
}

#define XLOG_FFI_EXPORT \
    extern "C" __attribute__((visibility("default"))) __attribute__((used))

using namespace mars::xlog;

XLOG_FFI_EXPORT
void xlog_ffi_open(int level,
                   int console_open,
                   const char* log_dir,
                   const char* cache_dir,
                   const char* name_prefix,
                   int cache_days,
                   const char* pub_key,
                   int compress_mode) {
    XLogConfig config;
    config.mode_ = kAppenderAsync;
    config.logdir_ = log_dir ? log_dir : "";
    config.nameprefix_ = name_prefix ? name_prefix : "";
    config.pub_key_ = pub_key ? pub_key : "";
    config.compress_mode_ = (compress_mode == 1) ? kZstd : kZlib;
    config.compress_level_ = 0;
    config.cachedir_ = cache_dir ? cache_dir : "";
    config.cache_days_ = cache_days;
    appender_open(config);
    xlogger_SetLevel((TLogLevel)level);
    appender_set_console_log(console_open != 0);
}

XLOG_FFI_EXPORT
void xlog_ffi_set_level(int level) {
    xlogger_SetLevel((TLogLevel)level);
}

XLOG_FFI_EXPORT
int xlog_ffi_get_level(void) {
    return (int)xlogger_Level();
}

XLOG_FFI_EXPORT
int xlog_ffi_is_enabled(int level) {
    return xlogger_IsEnabledFor((TLogLevel)level);
}

XLOG_FFI_EXPORT
void xlog_ffi_log(int level, const char* tag, const char* msg, int msg_len) {
    (void)msg_len;  // mars' xlogger_Write consumes a NUL-terminated C string.
    XLoggerInfo info;
    memset(&info, 0, sizeof(info));
    info.level = (TLogLevel)level;
    info.tag = tag ? tag : "";
    info.filename = "";
    info.func_name = "";
    info.line = 0;
    gettimeofday(&info.timeval, NULL);
    info.pid = xlogger_pid();
    info.tid = xlogger_tid();
    info.maintid = xlogger_maintid();
    xlogger_Write(&info, msg ? msg : "");
}

XLOG_FFI_EXPORT
void xlog_ffi_flush(int sync) {
    if (sync) {
        appender_flush_sync();
    } else {
        appender_flush();
    }
}

XLOG_FFI_EXPORT
void xlog_ffi_close(void) {
    appender_close();
}
