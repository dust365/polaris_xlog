// xlog_ffi.cc — extern "C" shim bridging dart:ffi to mars-xlog's C++ API.
//
// ANDROID build of the shim. The iOS counterpart is ios/Classes/xlog_ffi.mm,
// which shares the same extern "C" surface but uses the framework header layout
// (keep the two in sync). See docs/ffi_0.2.0_plan.md §3 for why iOS compiles the
// shim into the plugin Pod instead of into mars.
//
// mars exposes its logger as C++ (std::string config, C++ linkage), which FFI
// cannot bind to directly. This thin layer wraps the process-global appender +
// xlogger write path used by mars' own single-instance integrations (and by the
// iOS XLogBridge.mm), so the .xlog output format is identical.
//
// Build wiring (Android): build_android.sh copies this file (and xlog_ffi.h)
// into the staged mars tree under xlog/src/, where xlog/CMakeLists.txt's
// `src/*.cc` glob compiles it into libxlog; the marsxlog target then force-loads
// the symbols (-Wl,-u) and exports them via export.exp so they land in
// libmarsxlog.so for Dart's DynamicLibrary.open to dlsym.

#include "xlog_ffi.h"

#include <stdint.h>
#include <string.h>
#include <sys/time.h>

#include <string>

// Source-tree-relative includes (resolved via xlog/CMakeLists.txt's
// include_directories): appender.h lives in xlog/, xloggerbase.h in
// comm/xlogger/.
#include "appender.h"
#include "xloggerbase.h"

// visibility("default"): export the symbol from the shared object / dylib.
// used: keep it even though nothing in the native build references it (it is
// only ever reached via dlsym from Dart) — defends against compiler/linker
// dead-stripping. See docs/ffi_0.2.0_plan.md §2/§3.
#define XLOG_FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))

using namespace mars::xlog;

extern "C" {

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
    // Default zlib keeps the pure-Dart decoder working (lib/src/xlog_decoder.dart).
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

}  // extern "C"
