import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polaris_xlog/polaris_xlog.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodeBytes decodes uncompressed nocrypt block', () {
    final bytes = _plainBlock('hello mars\n');
    expect(XLogDecoder.decodeBytes(bytes), 'hello mars\n');
  });

  test('decodeBytes returns empty string for invalid input', () {
    expect(XLogDecoder.decodeBytes(const [0xFF, 0xFF]), '');
  });

  test('decodeFile decodes via worker isolate', () async {
    final dir = await Directory.systemTemp.createTemp('xlog_decoder_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.xlog');
    await file.writeAsBytes(_plainBlock('isolate ok\n'));
    expect(await XLogDecoder.decodeFile(file.path), 'isolate ok\n');
  });

  test('decodeFile rejects oversized files', () async {
    final dir = await Directory.systemTemp.createTemp('xlog_decoder_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/big.xlog');
    final raf = await file.open(mode: FileMode.write);
    await raf.truncate(XLogDecoder.maxDecodeFileBytes + 1);
    await raf.close();
    expect(
      () => XLogDecoder.decodeFile(file.path),
      throwsA(isA<XLogDecodeFileTooLargeException>()),
    );
  });
}
