/// Log levels, mapped 1:1 to mars-xlog's native levels.
///
/// Native order (Android `Xlog`/iOS `TLogLevel`):
/// 0 = verbose, 1 = debug, 2 = info, 3 = warning, 4 = error, 5 = fatal, 6 = none.
enum XLogLevel {
  verbose(0),
  debug(1),
  info(2),
  warn(3),
  error(4),
  fatal(5),
  none(6);

  const XLogLevel(this.value);

  /// The integer value passed to the native layer.
  final int value;
}
