import 'package:flutter/services.dart';

import 'xlog_decoder.dart';
import 'xlog_file.dart';
import 'xlog_level.dart';

/// High-level Dart API over Tencent mars-xlog.
///
/// Typical lifecycle:
/// ```dart
/// await XLog.init(namePrefix: 'mlog');
/// XLog.i('App', 'started');
/// XLog.w('Net', 'slow response');
/// XLog.e('DB', 'write failed', error: e, stackTrace: s);
/// await XLog.flush();          // before reading/uploading
/// await XLog.close();          // on app shutdown
/// ```
///
/// mars-xlog writes one encrypted, mmap-buffered file **per calendar day**
/// (`<prefix>_YYYYMMDD.xlog`). Old files are pruned after [cacheDays].
class XLog {
  XLog._();

  static const MethodChannel _channel = MethodChannel('com.youfi/xlog_plugin');

  static bool _initialized = false;
  static String _defaultTag = 'MLog';

  /// Whether [init] has completed successfully.
  static bool get isInitialized => _initialized;

  /// Initialize the native logger and open the daily appender.
  ///
  /// [level] – minimum level that gets written.
  /// [consoleLogOpen] – mirror logs to logcat (Android) / Xcode console (iOS)
  /// in addition to writing `.xlog` files. Does not affect file output.
  /// Recommended: `consoleLogOpen: kDebugMode`.
  /// [namePrefix] – file name prefix; files become `<namePrefix>_YYYYMMDD.xlog`.
  /// [cacheDays] – days to keep mmap cache files (0 = write straight to log dir).
  /// [pubKey] – optional ECDH public key (hex) to encrypt logs at rest.
  static Future<void> init({
    XLogLevel level = XLogLevel.info,
    bool consoleLogOpen = false,
    String namePrefix = 'mlog',
    String defaultTag = 'MLog',
    int cacheDays = 0,
    String? pubKey,
  }) async {
    _defaultTag = defaultTag;
    await _channel.invokeMethod<void>('init', {
      'level': level.value,
      'consoleLogOpen': consoleLogOpen,
      'namePrefix': namePrefix,
      'cacheDays': cacheDays,
      'pubKey': pubKey ?? '',
    });
    _initialized = true;
  }

  /// Change the minimum log level at runtime.
  static Future<void> setLevel(XLogLevel level) =>
      _channel.invokeMethod<void>('setLevel', {'level': level.value});

  static void v(String tag, String msg) => _write(XLogLevel.verbose, tag, msg);
  static void d(String tag, String msg) => _write(XLogLevel.debug, tag, msg);
  static void i(String tag, String msg) => _write(XLogLevel.info, tag, msg);
  static void w(String tag, String msg) => _write(XLogLevel.warn, tag, msg);

  /// Error log. Optionally append [error] and [stackTrace] to the message.
  static void e(String tag, String msg, {Object? error, StackTrace? stackTrace}) {
    final buf = StringBuffer(msg);
    if (error != null) buf.write('\n$error');
    if (stackTrace != null) buf.write('\n$stackTrace');
    _write(XLogLevel.error, tag, buf.toString());
  }

  static void _write(XLogLevel level, String tag, String msg) {
    // Fire-and-forget: logging must never block or throw into business code.
    _channel.invokeMethod<void>('log', {
      'level': level.value,
      'tag': tag.isEmpty ? _defaultTag : tag,
      'msg': msg,
    });
  }

  /// Flush the mmap buffer to disk. Call before reading or uploading files.
  /// [sync] true blocks until the write completes.
  static Future<void> flush({bool sync = true}) =>
      _channel.invokeMethod<void>('flush', {'sync': sync});

  /// Flush and close the appender. Call on app termination.
  static Future<void> close() async {
    await _channel.invokeMethod<void>('close');
    _initialized = false;
  }

  /// Absolute directory holding the `.xlog` files.
  static Future<String> getLogDir() async =>
      (await _channel.invokeMethod<String>('getLogDir'))!;

  /// All daily log files currently on disk, newest day first.
  static Future<List<XLogFile>> listLogFiles() async {
    final raw = await _channel.invokeListMethod<dynamic>('listLogFiles') ?? [];
    final files = raw
        .map((e) => XLogFile.fromMap(e as Map))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return files;
  }

  /// Returns the log file for [date] (defaults to today), or null if none.
  ///
  /// Useful when uploading: call [flush] first, then read `.path` and send it
  /// with your own HTTP client. The plugin intentionally ships no networking
  /// dependency — uploading is left to the app.
  static Future<XLogFile?> logFileForDate([DateTime? date]) async {
    final day = date ?? DateTime.now();
    final files = await listLogFiles();
    for (final f in files) {
      if (f.date.year == day.year &&
          f.date.month == day.month &&
          f.date.day == day.day) {
        return f;
      }
    }
    return null;
  }

  /// Decode a `.xlog` file at [filePath] into plain text on-device.
  ///
  /// Flushes first so the current day's buffered logs are included when
  /// reading today's file. Decoding runs in a worker isolate (via
  /// [XLogDecoder.decodeFile]) so large files do not block the UI thread.
  /// Only works for logs written without a `pubKey` (the plugin default);
  /// encrypted/zstd blocks are annotated and skipped.
  ///
  /// Files larger than [XLogDecoder.maxDecodeFileBytes] (10 MiB) throw
  /// [XLogDecodeFileTooLargeException] — upload them instead.
  /// Useful for an in-app log viewer; decoded text still occupies memory.
  static Future<String> decodeLogFile(String filePath) async {
    await flush(sync: true);
    return XLogDecoder.decodeFile(filePath);
  }
}
