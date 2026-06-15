import 'dart:io';

import 'package:dio/dio.dart';
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
  /// [consoleLogOpen] – also echo to logcat / Xcode console (debug only).
  /// [namePrefix] – file name prefix; files become `<namePrefix>_YYYYMMDD.xlog`.
  /// [cacheDays] – days to keep mmap cache files (0 = write straight to log dir).
  /// [pubKey] – optional ECDH public key (hex) to encrypt logs at rest.
  static Future<void> init({
    XLogLevel level = XLogLevel.info,
    bool consoleLogOpen = true,
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
  /// reading today's file. Only works for logs written without a `pubKey`
  /// (the plugin default); encrypted/zstd blocks are annotated and skipped.
  /// Useful for an in-app log viewer.
  static Future<String> decodeLogFile(String filePath) async {
    await flush(sync: true);
    return XLogDecoder.decodeFile(filePath);
  }

  /// Upload a single day's log file to [url] via multipart POST (dio).
  ///
  /// Flushes first so the current day's in-memory buffer is on disk.
  /// [date] defaults to today. [fields] are extra form fields (e.g. userId,
  /// appVersion). [headers] are extra HTTP headers (e.g. auth token).
  /// [fieldName] is the multipart field carrying the file (default `file`).
  /// Pass [dio] to reuse the app's configured instance (interceptors, baseUrl,
  /// auth). [onSendProgress] reports upload progress.
  ///
  /// Returns the [XLogUploadResult]. Throws [StateError] if the file is absent.
  static Future<XLogUploadResult> uploadLog({
    required String url,
    DateTime? date,
    Map<String, dynamic> fields = const {},
    Map<String, dynamic> headers = const {},
    String fieldName = 'file',
    Dio? dio,
    ProgressCallback? onSendProgress,
  }) async {
    await flush(sync: true);
    final logFile = await logFileForDate(date);
    if (logFile == null) {
      throw StateError('No log file for ${date ?? DateTime.now()}');
    }
    return uploadFile(
      url: url,
      filePath: logFile.path,
      fields: fields,
      headers: headers,
      fieldName: fieldName,
      dio: dio,
      onSendProgress: onSendProgress,
    );
  }

  /// Upload an arbitrary log file path. Used by [uploadLog] and the dev-mode UI.
  ///
  /// Pass [dio] to reuse the app's configured instance; otherwise a default
  /// [Dio] is created. `validateStatus` is relaxed so non-2xx responses are
  /// returned (not thrown) and surfaced via [XLogUploadResult.isSuccess].
  static Future<XLogUploadResult> uploadFile({
    required String url,
    required String filePath,
    Map<String, dynamic> fields = const {},
    Map<String, dynamic> headers = const {},
    String fieldName = 'file',
    Dio? dio,
    ProgressCallback? onSendProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('Log file not found: $filePath');
    }
    final fileName = file.uri.pathSegments.last;
    final formData = FormData.fromMap({
      ...fields,
      fieldName: await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final client = dio ?? Dio();
    final response = await client.post<dynamic>(
      url,
      data: formData,
      options: Options(
        headers: headers.isEmpty ? null : headers,
        validateStatus: (_) => true,
      ),
      onSendProgress: onSendProgress,
    );
    return XLogUploadResult(
      statusCode: response.statusCode ?? 0,
      body: response.data?.toString() ?? '',
      fileName: fileName,
    );
  }
}

/// Result of a log upload.
class XLogUploadResult {
  const XLogUploadResult({
    required this.statusCode,
    required this.body,
    required this.fileName,
  });

  final int statusCode;
  final String body;
  final String fileName;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  @override
  String toString() => 'XLogUploadResult($fileName -> $statusCode)';
}
