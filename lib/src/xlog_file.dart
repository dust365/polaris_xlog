/// Metadata for one on-disk log file.
///
/// mars-xlog rotates files daily and names them `<prefix>_YYYYMMDD.xlog`,
/// so each [XLogFile] corresponds to exactly one calendar day.
class XLogFile {
  const XLogFile({
    required this.path,
    required this.name,
    required this.date,
    required this.sizeBytes,
  });

  /// Absolute path on the device.
  final String path;

  /// File name, e.g. `mlog_20260610.xlog`.
  final String name;

  /// The calendar day this file holds logs for, parsed from the file name.
  final DateTime date;

  /// File size in bytes.
  final int sizeBytes;

  factory XLogFile.fromMap(Map<dynamic, dynamic> map) {
    final name = map['name'] as String;
    return XLogFile(
      path: map['path'] as String,
      name: name,
      date: _parseDate(name),
      sizeBytes: (map['size'] as num).toInt(),
    );
  }

  /// Extracts the `YYYYMMDD` token from `<prefix>_YYYYMMDD.xlog`.
  static DateTime _parseDate(String name) {
    final match = RegExp(r'(\d{8})').firstMatch(name);
    if (match == null) return DateTime.fromMillisecondsSinceEpoch(0);
    final s = match.group(1)!;
    return DateTime(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );
  }

  @override
  String toString() => 'XLogFile($name, ${sizeBytes}B)';
}
