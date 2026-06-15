# xlog_plugin

基于腾讯 [mars-xlog](https://github.com/Tencent/mars) 的 Flutter 日志插件。提供高性能、加密、按天滚动的本地日志，并内置「开发者模式上传日志」能力。

## 特性

- **按天归类**：mars-xlog 原生按日期滚动，每天一个文件 `<prefix>_YYYYMMDD.xlog`，无需自己管理。
- **高性能**：mmap 缓冲 + 异步写入，主线程几乎零开销。
- **加密**：可选 ECDH 公钥加密磁盘日志。
- **统一 Dart API**：`XLog.init() / .i() / .w() / .e() / .close()`。
- **开发者模式上传**：列出每天的日志文件，点击即可 multipart POST 上传到后端。

## 安装

在 app 的 `pubspec.yaml`：

```yaml
dependencies:
  xlog_plugin:
    path: packages/xlog_plugin
```

## 使用

```dart
import 'package:xlog_plugin/xlog_plugin.dart';

await XLog.init(
  level: XLogLevel.verbose,
  namePrefix: 'mlog',   // 文件名 mlog_YYYYMMDD.xlog
  cacheDays: 7,         // mmap 缓存保留天数
  consoleLogOpen: true, // 同时输出到 logcat / Xcode 控制台
);

XLog.i('App', 'started');
XLog.w('Net', 'slow response');
XLog.e('DB', 'write failed', error: e, stackTrace: s);

await XLog.flush();  // 读取/上传前先 flush
await XLog.close();  // App 退出时
```

### 上传当天日志

上传基于 **dio**（multipart）。可传入项目里已配置好的 `Dio` 实例，复用其 `baseUrl`、拦截器、鉴权等：

```dart
final result = await XLog.uploadLog(
  url: 'https://logs.youfi.com/api/v1/upload',
  fields: {'userId': 'huichen@youfi.com'},
  headers: {'Authorization': 'Bearer <token>'},
  dio: appDio,                       // 可选：复用项目的 Dio
  onSendProgress: (sent, total) {},  // 可选：上传进度
);
print(result.isSuccess); // 2xx
```

`uploadLog` 会先 flush，再选中对应日期（默认今天）的文件上传。后端按 `file`（multipart 字段名）接收 `.xlog` 文件即可。开发者模式整页示例见 `example/lib/developer_log_page.dart`。

> `.xlog` 是加密/压缩格式，后端需用 mars 提供的 `decode_mars_nocrypt_log_file.py` 解码后查看。

### App 内查看日志（无需后端）

`.xlog` 默认是 zlib 压缩（不加密，未传 `pubKey`），插件内置了一个纯 Dart 解码器，可直接在设备上解码成文本，做「开发者模式」日志查看器：

```dart
final text = await XLog.decodeLogFile(file.path); // 先 flush 再解码
final lines = const LineSplitter().convert(text);
```

整页示例见 `example/lib/log_viewer_page.dart`：支持按级别着色（I/W/E）、关键字过滤、一键复制。

> 解码器移植自 mars 官方 `decode_mars_nocrypt_log_file.py`，仅支持未加密（无 `pubKey`）的 zlib 日志；若使用了 ECDH `pubKey` 加密，需在后端用私钥解密。zstd 压缩的块会被跳过（mars 默认 zlib）。

## API 一览

| 方法 | 说明 |
|------|------|
| `XLog.init(...)` | 初始化并打开当天 appender |
| `XLog.v/d/i/w/e(tag, msg)` | 按级别写日志 |
| `XLog.setLevel(level)` | 运行时改最低级别 |
| `XLog.flush({sync})` | 刷盘 |
| `XLog.close()` | 刷盘并关闭 |
| `XLog.getLogDir()` | 日志目录绝对路径 |
| `XLog.listLogFiles()` | 列出每天的日志文件（按日期倒序） |
| `XLog.logFileForDate([date])` | 取某天的文件 |
| `XLog.uploadLog(url:...)` | 上传某天日志（默认今天） |
| `XLog.uploadFile(url:..., filePath:...)` | 上传任意文件 |
| `XLog.decodeLogFile(path)` | 在设备上把 `.xlog` 解码成纯文本（用于 App 内查看） |

## 平台集成

### Android

`android/build.gradle` 已直接依赖：

```gradle
implementation 'com.tencent.mars:mars-xlog:1.2.5'
```

胶水代码 `XlogPlugin.kt` 调用 `Xlog` / `Log.appenderOpen(...)`，日志目录为 `filesDir/xlog`。minSdk 21。

### iOS

mars-xlog **不在 CocoaPods trunk 上**，需二选一（见 `ios/xlog_plugin.podspec` 注释）：

1. **依赖 git 源（推荐用 podspec 注释里的方式）**：在 example app 的 `ios/Podfile` 中加
   `pod 'mars', :git => 'https://github.com/Tencent/mars.git', :tag => 'v1.2.5'`（见 `example/ios/PodfileSnippet.txt`）。
2. **vendored framework**：自行编译出 `mars.framework` 放入 `ios/Frameworks/`，在 podspec 中启用 `vendored_frameworks`。

Swift 插件 `XlogPlugin.swift` 通过 ObjC++ 桥接 `XLogBridge.mm` 调用 mars 的 C++ appender API。日志目录为 `Documents/xlog`。

> mars 的 C++ 头文件路径（`<mars/xlog/xlogger.h>`、`<mars/xlog/appender.h>`）与具体 struct 字段（如 `XLogConfig`）随版本略有差异；若编译报符号找不到，请对照所用 mars 版本的头文件微调 `XLogBridge.mm`。

## 目录结构

```
packages/xlog_plugin/
├── lib/
│   ├── xlog_plugin.dart        # 导出
│   └── src/
│       ├── xlog.dart           # Dart API + 上传逻辑
│       ├── xlog_level.dart
│       └── xlog_file.dart
├── android/                    # Kotlin 胶水 + Gradle (mars-xlog:1.2.5)
├── ios/                        # Swift 胶水 + ObjC++ 桥接 + podspec
├── example/                    # 含开发者模式上传页
└── test/
```

## MethodChannel

所有平台统一使用 channel 名 `com.youfi/xlog_plugin`。
