import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Thrown when [XLogDecoder.decodeFile] refuses to decode an oversized `.xlog`.
class XLogDecodeFileTooLargeException implements Exception {
  const XLogDecodeFileTooLargeException({
    required this.fileBytes,
    required this.maxBytes,
    required this.path,
  });

  final int fileBytes;
  final int maxBytes;
  final String path;

  @override
  String toString() =>
      'Log file too large to decode on device (${_fmt(fileBytes)} > ${_fmt(maxBytes)} limit): $path. '
      'Upload the file instead.';
}

String _fmt(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Pure-Dart decoder for Tencent mars `.xlog` files (no-crypt variants).
///
/// mars stores logs as a sequence of blocks. Each block has a 1-byte magic,
/// a small header, an optional crypt-key field, a zlib/zstd-compressed (or
/// raw) payload, and a trailing [_magicEnd] byte. This port mirrors the
/// official `decode_mars_nocrypt_log_file.py` so logs written **without** a
/// public key (the plugin's default) can be read on-device.
///
/// Limitations:
/// - Crypt variants (a real ECDH `pubKey` was used) can't be decoded here:
///   their payload stays encrypted without the private key.
/// - zstd-compressed blocks are skipped (no pure-Dart zstd); zlib is the
///   plugin's default so this rarely matters.
class XLogDecoder {
  XLogDecoder._();

  // Block magics (see mars appender). Names match the Python reference.
  static const int _ncStart = 0x03; // no compress
  static const int _ncStart1 = 0x06;
  static const int _ncNoCryptStart = 0x08;
  static const int _cStart = 0x04; // zlib compress
  static const int _cStart1 = 0x05; // zlib, length-prefixed sub-blocks
  static const int _cStart2 = 0x07;
  static const int _cNoCryptStart = 0x09; // zlib, no crypt (plugin default)
  static const int _syncZstdStart = 0x0A;
  static const int _syncNoCryptZstdStart = 0x0B;
  static const int _asyncZstdStart = 0x0C;
  static const int _asyncNoCryptZstdStart = 0x0D;
  static const int _magicEnd = 0x00;

  static const Set<int> _allStarts = {
    _ncStart, _ncStart1, _ncNoCryptStart, _cStart, _cStart1, _cStart2,
    _cNoCryptStart, _syncZstdStart, _syncNoCryptZstdStart, _asyncZstdStart,
    _asyncNoCryptZstdStart,
  };

  /// Maximum compressed `.xlog` size that [decodeFile] will read/decode on device.
  ///
  /// 10 MiB covers typical daily dev logs while keeping post-inflate memory
  /// bounded on mobile. Use upload + server-side decode for larger files.
  static const int maxDecodeFileBytes = 10 * 1024 * 1024;

  /// Read [path] and return the decoded plain-text log.
  ///
  /// Rejects files larger than [maxDecodeFileBytes] before reading. File I/O and
  /// CPU-heavy inflate run in a worker isolate so the UI thread stays responsive.
  /// Throws [XLogDecodeFileTooLargeException] or [FileSystemException] when the
  /// file is too large or missing. Undecodable (e.g. encrypted/zstd) blocks are
  /// annotated inline.
  static Future<String> decodeFile(String path) async {
    await _assertDecodeFileSize(path);
    return compute(decodeXLogFileInIsolate, path);
  }

  /// Synchronous read + decode for use inside [decodeXLogFileInIsolate] only.
  static String decodeFileSync(String path) {
    _assertDecodeFileSizeSync(path);
    final bytes = File(path).readAsBytesSync();
    return decodeBytes(bytes);
  }

  static Future<void> _assertDecodeFileSize(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Log file not found', path);
    }
    final size = await file.length();
    if (size > maxDecodeFileBytes) {
      throw XLogDecodeFileTooLargeException(
        fileBytes: size,
        maxBytes: maxDecodeFileBytes,
        path: path,
      );
    }
  }

  static void _assertDecodeFileSizeSync(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Log file not found', path);
    }
    final size = file.lengthSync();
    if (size > maxDecodeFileBytes) {
      throw XLogDecodeFileTooLargeException(
        fileBytes: size,
        maxBytes: maxDecodeFileBytes,
        path: path,
      );
    }
  }

  /// Decode raw `.xlog` [bytes] into plain text.
  static String decodeBytes(List<int> bytes) {
    final buf = bytes;
    final out = <int>[];
    var pos = _findStart(buf, 0);
    if (pos < 0) return '';
    while (pos >= 0 && pos < buf.length) {
      pos = _decodeBlock(buf, pos, out);
    }
    // mars writes UTF-8; tolerate stray bytes from partial blocks.
    return utf8.decode(out, allowMalformed: true);
  }

  static int _cryptKeyLen(int magic) {
    if (magic == _ncStart || magic == _cStart || magic == _cStart1) return 4;
    if (magic == _cStart2 ||
        magic == _ncStart1 ||
        magic == _ncNoCryptStart ||
        magic == _cNoCryptStart ||
        magic == _syncZstdStart ||
        magic == _syncNoCryptZstdStart ||
        magic == _asyncZstdStart ||
        magic == _asyncNoCryptZstdStart) {
      return 64;
    }
    return -1;
  }

  /// Validates the block at [offset]. Header layout:
  /// magic(1) seq(2) beginHour(1) endHour(1) length(4) cryptKey(cryptKeyLen).
  static bool _isGoodBlock(List<int> buf, int offset) {
    if (offset >= buf.length) return false;
    final magic = buf[offset];
    final ck = _cryptKeyLen(magic);
    if (ck < 0) return false;
    final headerLen = 1 + 2 + 1 + 1 + 4 + ck;
    if (offset + headerLen + 1 + 1 > buf.length) return false;
    final length = _u32(buf, offset + 5); // headerLen - 4 - ck == 5
    final endPos = offset + headerLen + length;
    if (endPos + 1 > buf.length) return false;
    return buf[endPos] == _magicEnd;
  }

  /// Scan forward from [from] for the first byte that begins a valid block.
  static int _findStart(List<int> buf, int from) {
    for (var i = from; i < buf.length; i++) {
      if (_allStarts.contains(buf[i]) && _isGoodBlock(buf, i)) return i;
    }
    return -1;
  }

  /// Decode one block, append its text to [out], return the next offset
  /// (or -1 when no further valid block exists).
  static int _decodeBlock(List<int> buf, int offset, List<int> out) {
    if (!_isGoodBlock(buf, offset)) {
      final fix = _findStart(buf, offset + 1);
      if (fix < 0) return -1;
      offset = fix;
    }
    final magic = buf[offset];
    final ck = _cryptKeyLen(magic);
    final headerLen = 1 + 2 + 1 + 1 + 4 + ck;
    final length = _u32(buf, offset + 5);
    final body = buf.sublist(offset + headerLen, offset + headerLen + length);
    final next = offset + headerLen + length + 1;

    try {
      if (magic == _cStart || magic == _cNoCryptStart) {
        out.addAll(_inflate(body));
      } else if (magic == _cStart1) {
        // Concatenate length-prefixed sub-blocks, then inflate.
        final joined = <int>[];
        var p = 0;
        while (p + 2 <= body.length) {
          final sl = body[p] | (body[p + 1] << 8);
          final start = p + 2;
          final end = (start + sl <= body.length) ? start + sl : body.length;
          joined.addAll(body.sublist(start, end));
          p = end;
        }
        out.addAll(_inflate(joined));
      } else if (magic == _ncStart ||
          magic == _ncStart1 ||
          magic == _ncNoCryptStart) {
        out.addAll(body); // stored, no compression
      } else {
        // Encrypted or zstd block: can't decode without key / zstd support.
        out.addAll(
            utf8.encode('[xlog] skipped undecodable block (magic=0x${magic.toRadixString(16)}, $length bytes)\n'));
      }
    } catch (_) {
      out.addAll(utf8.encode('[xlog] block decode error ($length bytes)\n'));
    }
    return next;
  }

  static int _u32(List<int> b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  /// Raw-deflate inflate that tolerates streams not terminated with a final
  /// block (mars flushes with Z_SYNC_FLUSH, so blocks may stay "open").
  static List<int> _inflate(List<int> data) {
    if (data.isEmpty) return const [];
    final filter = RawZLibFilter.inflateFilter(raw: true);
    filter.process(data, 0, data.length);
    final out = <int>[];
    List<int>? chunk;
    while ((chunk = filter.processed(flush: true)) != null) {
      out.addAll(chunk!);
    }
    return out;
  }
}

/// Worker-isolate entry: read [path] and decode off the UI isolate.
String decodeXLogFileInIsolate(String path) => XLogDecoder.decodeFileSync(path);
