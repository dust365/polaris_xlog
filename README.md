# xlog_plugin

基于腾讯 [mars-xlog](https://github.com/Tencent/mars) 的 Flutter 日志插件：高性能、按天滚动的本地日志，可选加密，内置纯 Dart 解码器。**零 Dart 第三方依赖**。
自己基于 mars 源码迁移到 master `6aa5b56`编译的最新版本

## 平台支持

| 平台 | 支持 | 说明 |
|------|------|------|
| Android 真机 | ✅ | **arm64-v8a only**，minSdk 21 |
| Android 模拟器 (x86/x86_64) | ❌ | 未 vendored 对应 ABI |
| iOS 真机 | ✅ | **arm64 only**，iOS 13+ |
| iOS 模拟器 | ❌ | xcframework 无 simulator slice |

## 特性

- **按天滚动**：`<prefix>_YYYYMMDD.xlog`，无需自行切文件。
- **高性能**：mmap 缓冲 + 异步写入。
- **可选加密**：`pubKey`（ECDH；Android 原生传参待完善）。
- **纯 Dart 解码**：默认 zlib、无加密日志可在 App 内 `decodeLogFile`（worker isolate，不阻塞 UI）。
- **控制台镜像**：`consoleLogOpen` 初始化开关（默认关；调试可用 `kDebugMode`）。
- **上传由业务实现**：插件不内置 HTTP 客户端（example 有 `http` 示范）。

## 安装

```yaml
dependencies:
  xlog_plugin: ^0.1.0
```

或 Git 依赖：

```yaml
dependencies:
  xlog_plugin:
    git:
      url: https://github.com/dust365/xlog_plugin.git
```

## 使用

```dart
import 'package:xlog_plugin/xlog_plugin.dart';

import 'package:flutter/foundation.dart';

await XLog.init(
  level: XLogLevel.info,
  namePrefix: 'mlog',
  cacheDays: 7,
  consoleLogOpen: kDebugMode, // true → logcat / Xcode；false → 仅写 .xlog
);

XLog.i('App', 'started');
await XLog.flush();
await XLog.close();
```

### 上传日志（业务层）

```dart
await XLog.flush(sync: true);
final file = await XLog.logFileForDate();
// 用项目里的 dio / http 上传 file.path
```

示例：`example/lib/developer_log_page.dart`。

### App 内查看

```dart
final text = await XLog.decodeLogFile(file.path);
```

限制：无 `pubKey` 的 zlib 块可解；加密 / zstd 块需后端或官方 Python 解码器。App 内解码上限 **10 MiB**（`XLogDecoder.maxDecodeFileBytes`），超出请上传后在服务端查看。

## API

| 方法 | 说明 |
|------|------|
| `XLog.init(...)` | 初始化 |
| `XLog.v/d/i/w/e` | 写日志 |
| `XLog.flush({sync})` | 刷盘 |
| `XLog.close()` | 关闭 |
| `XLog.listLogFiles()` | 列出 `.xlog` |
| `XLog.logFileForDate([date])` | 指定日期文件 |
| `XLog.decodeLogFile(path)` | 设备端解码 |

## 原生产物

| 平台 | 产物 | 体积（strip 后约） |
|------|------|-------------------|
| Android | `jniLibs/arm64-v8a/libmarsxlog.so` | ~747 KB |
| iOS | `Frameworks/mars.xcframework` | ~2.2 MB |

mars 源码 pin：`6aa5b56`。维护者重建见 [`native/README.md`](native/README.md)（**不在 pub 包内**）。

## 许可

MIT — 见 [LICENSE](LICENSE) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 链接

- 仓库：https://github.com/dust365/xlog_plugin
- 问题反馈：https://github.com/dust365/xlog_plugin/issues
