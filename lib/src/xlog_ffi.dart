import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'xlog_ffi_bindings.dart';

/// Per-isolate FFI gateway to the mars-xlog hot path.
///
/// Hot-path logging (`log` / `flush` / `setLevel` / `close`) goes straight to
/// native via `dart:ffi`, so it works from any isolate without a
/// `RootIsolateToken` and never round-trips through the platform channel
/// (see docs/ffi_0.2.0_plan.md §5). Cold paths that need the app sandbox
/// directory (`init` / `listLogFiles` / `getLogDir`) stay on the MethodChannel.
///
/// There is no MethodChannel fallback: if the native library cannot be loaded
/// the failure is fatal by design (plan §11) — surfaced as an exception on first
/// use rather than silently degrading.
class XLogFfi {
  XLogFfi._(this._bindings);

  final XLogFfiBindings _bindings;

  /// Lazily-created, one instance per isolate (each isolate has its own native
  /// library handle and scratch buffers; isolates never share Dart memory).
  static XLogFfi? _instance;

  static XLogFfi get instance => _instance ??= XLogFfi._(XLogFfiBindings(_load()));

  static ffi.DynamicLibrary _load() {
    // Android: the FFI shim is compiled into libmarsxlog.so (dlopen is
    // refcounted, so this coexists with Kotlin's System.loadLibrary).
    if (Platform.isAndroid) return ffi.DynamicLibrary.open('libmarsxlog.so');
    // iOS: the shim is compiled into the plugin's own dynamic
    // xlog_plugin.framework (embedded + loaded at launch), so the symbols are
    // already in the process image — look them up there (plan §3).
    if (Platform.isIOS) return ffi.DynamicLibrary.process();
    throw UnsupportedError(
        'xlog_plugin FFI only supports Android and iOS (got ${Platform.operatingSystem}).');
  }

  // Reusable native scratch buffers grown on demand, so a steady stream of logs
  // does not malloc/free per call. tag and msg need to be alive simultaneously,
  // hence two slots. Freed implicitly when the isolate (and its heap) dies.
  final _ScratchBuffer _tag = _ScratchBuffer();
  final _ScratchBuffer _msg = _ScratchBuffer();

  /// Write one log line. Returns immediately; mars buffers in mmap and writes
  /// on its own thread. [tag] and [msg] are UTF-8 encoded into reused buffers.
  void log(int level, String tag, String msg) {
    _tag.writeUtf8(tag);
    final msgLen = _msg.writeUtf8(msg);
    _bindings.xlog_ffi_log(level, _tag.ptr.cast(), _msg.ptr.cast(), msgLen);
  }

  /// Change the global minimum level.
  void setLevel(int level) => _bindings.xlog_ffi_set_level(level);

  /// Current global level (mars TLogLevel).
  int getLevel() => _bindings.xlog_ffi_get_level();

  /// Whether [level] would be written natively.
  bool isEnabled(int level) => _bindings.xlog_ffi_is_enabled(level) != 0;

  /// Flush the mmap buffer to disk. [sync] blocks until the write completes.
  void flush({bool sync = true}) => _bindings.xlog_ffi_flush(sync ? 1 : 0);

  /// Flush and close the global appender.
  void close() => _bindings.xlog_ffi_close();

  /// Open the appender directly over FFI. Normally unused — `init` runs on the
  /// MethodChannel to obtain the sandbox path — but handy for tests/tools.
  void open({
    required int level,
    required bool consoleOpen,
    required String logDir,
    required String cacheDir,
    required String namePrefix,
    required int cacheDays,
    String pubKey = '',
    int compressMode = 0,
  }) {
    final dir = logDir.toNativeUtf8();
    final cache = cacheDir.toNativeUtf8();
    final prefix = namePrefix.toNativeUtf8();
    final key = pubKey.toNativeUtf8();
    try {
      _bindings.xlog_ffi_open(level, consoleOpen ? 1 : 0, dir.cast(),
          cache.cast(), prefix.cast(), cacheDays, key.cast(), compressMode);
    } finally {
      malloc
        ..free(dir)
        ..free(cache)
        ..free(prefix)
        ..free(key);
    }
  }
}

/// A growable native UTF-8 buffer reused across calls to avoid per-log malloc.
class _ScratchBuffer {
  ffi.Pointer<ffi.Uint8> ptr = ffi.nullptr;
  int _capacity = 0;

  /// Encode [s] (plus a NUL terminator) into the buffer, growing if needed.
  /// Returns the byte length of the UTF-8 content (excluding the terminator).
  int writeUtf8(String s) {
    final bytes = utf8.encode(s);
    final need = bytes.length + 1;
    if (_capacity < need) {
      if (ptr != ffi.nullptr) malloc.free(ptr);
      // Over-allocate a little to amortize growth for fluctuating message sizes.
      _capacity = need < 256 ? 256 : need;
      ptr = malloc<ffi.Uint8>(_capacity);
    }
    final view = ptr.asTypedList(_capacity);
    view.setRange(0, bytes.length, bytes);
    view[bytes.length] = 0;
    return bytes.length;
  }
}
