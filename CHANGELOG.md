# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-16

### Added

- Dart API: `XLog.init`, level methods, `flush`, `close`, `listLogFiles`,
  `logFileForDate`, `decodeLogFile`.
- Pure-Dart decoder for default zlib, no-encryption `.xlog` files.
- Vendored mars-xlog built from source (mars commit `6aa5b56`).
- Android: `arm64-v8a` only, `c++_static` `libmarsxlog.so`.
- iOS: device-only `arm64` `mars.xcframework` (no simulator slice).
- Example app with log viewer and upload demo (HTTP in example only).

### Notes

- Log upload is intentionally **not** bundled; apps use their own HTTP client.
- iOS Simulator and Android x86 emulators are **not** supported in this release.
- ECDH `pubKey` encryption: API surface exists; Android native wiring pending.

[0.1.0]: https://github.com/dust365/xlog_plugin/releases/tag/v0.1.0
