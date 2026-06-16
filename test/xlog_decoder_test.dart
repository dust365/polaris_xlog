import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_plugin/xlog_plugin.dart';

/// Builds a minimal mars no-compress, no-crypt block (magic 0x08).
List<int> _plainBlock(String text) {
  final body = utf8.encode(text);
  const headerLen = 1 + 2 + 1 + 1 + 4 + 64;
  final out = List<int>.filled(headerLen + body.length + 1, 0);
  out[0] = 0x08; // _ncNoCryptStart
  out[5] = body.length;
  out[6] = body.length >> 8;
  out.setRange(headerLen, headerLen + body.length, body);
  out[headerLen + body.length] = 0x00; // magic end
  return out;
}

void main() {
  test('decodeBytes decodes uncompressed nocrypt block', () {
    final bytes = _plainBlock('hello mars\n');
    expect(XLogDecoder.decodeBytes(bytes), 'hello mars\n');
  });

  test('decodeBytes returns empty string for invalid input', () {
    expect(XLogDecoder.decodeBytes(const [0xFF, 0xFF]), '');
  });
}
