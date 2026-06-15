import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_plugin/xlog_plugin.dart';

void main() {
  group('XLogDecoder', () {
    test('decodes a real no-crypt zlib .xlog sample to plain text', () async {
      final path = 'test/sample.xlog';
      if (!File(path).existsSync()) {
        // Sample is device-captured and optional in CI.
        return;
      }
      final text = await XLogDecoder.decodeFile(path);
      expect(text, contains('MLog example started'));
      expect(text, contains('[W]'));
      expect(text, contains('warning tapped'));
      expect(text, contains('[E]'));
      expect(text, contains('error tapped'));
      expect(text, contains('Exception: boom'));
    });

    test('returns empty string for non-xlog bytes', () {
      expect(XLogDecoder.decodeBytes([1, 2, 3, 4, 5]), '');
    });
  });
}
