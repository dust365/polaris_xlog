# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-06-24

### Added

- **FFI 热路径**：`v/d/i/w/e`、`setLevel`、`flush`、`close` 经 `dart:ffi` 直调 `xlog_ffi_*`，可在**任意 isolate** 写日志。
- `package:ffi` 运行时依赖；`ffigen` 生成 `xlog_ffi_bindings.dart`（维护者 dev 依赖）。
- FFI 壳源码：`native/src/xlog_ffi.{h,cc}`（Android 链入 `libmarsxlog.so`）、`ios/Classes/xlog_ffi.mm`。
- 每 isolate 复用 UTF-8 scratch buffer，减少高频 `malloc/free`。

### Changed

- **包名** `polaris_xlog`（入口 `package:polaris_xlog/polaris_xlog.dart`）；MethodChannel / Android package：`com.polaris.xlog`。
- **移除 Android Java mars 胶水**（`com.tencent.mars.xlog.*`）：appender 打开与读写全部由 Dart FFI 驱动；消费者 **无需 ProGuard keep 规则**。
- **移除 iOS `XLogBridge`**：冷路径仅保留目录解析；热路径走 FFI。
- `init`：channel 只返回 `logDir` / `cacheDir`，`xlog_ffi_open` 在 Dart 侧调用。
- 文档与示例对齐 0.2.0 架构；`native/build_*.sh` 校验 Android FFI 符号导出。

### Notes

- 平台约束不变：Android **arm64-v8a only**、iOS **device arm64 only**（无模拟器 slice）。
- 原生库加载失败为致命错误，无 MethodChannel fallback。
- mars 源码仍 pin 在 `6aa5b56`。

## [0.1.0] - 2026-06-16

### Added

- Dart API: `XLog.init`, level methods, `flush`, `close`, `listLogFiles`,
  `logFileForDate`, `decodeLogFile`.
- Pure-Dart decoder for default zlib, no-encryption `.xlog` files (worker isolate; 10 MiB on-device limit).
- Vendored mars-xlog built from source (mars commit `6aa5b56`).
- Android: `arm64-v8a` only, `c++_static` `libmarsxlog.so`.
- iOS: device-only `arm64` `mars.xcframework` (no simulator slice).
- Example app with log viewer and upload demo (HTTP in example only).

### Notes

- Log upload is intentionally **not** bundled; apps use their own HTTP client.
- iOS Simulator and Android x86 emulators are **not** supported in this release.
- `consoleLogOpen` init flag (default `false`; mirrors to logcat / Xcode when enabled).

[0.2.0]: https://github.com/dust365/polaris_xlog/releases/tag/v0.2.0
[0.1.0]: https://github.com/dust365/polaris_xlog/releases/tag/v0.1.0
