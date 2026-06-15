import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_plugin/xlog_plugin.dart';

void main() {
  group('XLogFile.fromMap', () {
    test('parses YYYYMMDD date from the file name', () {
      final f = XLogFile.fromMap({
        'path': '/data/xlog/mlog_20260610.xlog',
        'name': 'mlog_20260610.xlog',
        'size': 2048,
      });
      expect(f.date, DateTime(2026, 6, 10));
      expect(f.sizeBytes, 2048);
      expect(f.name, 'mlog_20260610.xlog');
    });

    test('falls back to epoch when no date token present', () {
      final f = XLogFile.fromMap({
        'path': '/data/xlog/weird.xlog',
        'name': 'weird.xlog',
        'size': 0,
      });
      expect(f.date, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  group('XLogLevel', () {
    test('native values match mars-xlog ordering', () {
      expect(XLogLevel.verbose.value, 0);
      expect(XLogLevel.info.value, 2);
      expect(XLogLevel.error.value, 4);
      expect(XLogLevel.none.value, 6);
    });
  });
}
