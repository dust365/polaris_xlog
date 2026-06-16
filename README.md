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

### 上传日志（由业务层实现）

插件**不内置任何网络库**，上传交给 App 自己做：先 `flush`，再用 `logFileForDate` /
`listLogFiles` 拿到文件路径，用你项目里现有的 HTTP 客户端发出去。下面用 `package:http`
举例（dio 同理）：

```dart
await XLog.flush(sync: true);
final file = await XLog.logFileForDate();      // 默认今天
if (file != null) {
  final req = http.MultipartRequest('POST', Uri.parse('https://logs.youfi.com/api/v1/upload'))
    ..fields['userId'] = 'huichen@youfi.com'
    ..files.add(await http.MultipartFile.fromPath('file', file.path));
  final res = await req.send();
  print(res.statusCode);
}
```

开发者模式整页示例见 `example/lib/developer_log_page.dart`。

> `.xlog` 是压缩（可选加密）格式，后端需用 mars 提供的 `decode_mars_nocrypt_log_file.py` 解码后查看。

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
| `XLog.logFileForDate([date])` | 取某天的文件（上传时拿路径用） |
| `XLog.decodeLogFile(path)` | 在设备上把 `.xlog` 解码成纯文本（用于 App 内查看） |

## 平台集成

> 两端的 mars 原生产物都从 **同一份 vendored 源码**（`native/mars/`，钉死在
> `native/MARS_VERSION = 6aa5b56`）编译而来。构建与升级流程见
> [`native/README.md`](native/README.md)。

### Android

mars-xlog 从源码编译后 vendored 进插件（不再用 Maven 制品）：

- 各 ABI 的 `libmarsxlog.so` + `libc++_shared.so` → `android/src/main/jniLibs/<abi>/`
- Java 胶水类 `Xlog.java` / `Log.java` → `android/src/main/java/com/tencent/mars/xlog/`

重建：`bash native/build_android.sh`。胶水代码 `XlogPlugin.kt` 调用 `Xlog` /
`Log.appenderOpen(...)`，日志目录为 `filesDir/xlog`。minSdk 21。

### iOS

mars-xlog **不在 CocoaPods trunk 上，也不提供预编译包**，因此本插件 **vendored 一个从源码编译的 `mars.xcframework`**（已随仓库提交，位于 `ios/Frameworks/mars.xcframework`，含 **真机 arm64 + 模拟器 arm64/x86_64** 三个切片）。podspec 已配置 `vendored_frameworks`，`pod install` 即可，无需额外操作。

Swift 插件 `XlogPlugin.swift` 通过 ObjC++ 桥接 `XLogBridge.mm` 调用 mars 的 C++ appender API（`<mars/xlog/appender.h>` + `<mars/xlog/xloggerbase.h>`）。日志目录为 `Documents/xlog`。

实现要点（踩坑记录）：

- 只 include `xloggerbase.h`（纯 `extern "C"`），不 include `xlogger.h`（它用相对路径 `#include "mars/comm/string_cast.h"`，与 framework 的 `Headers/{comm,xlog}` 布局不匹配）。
- mars 的 `comm/strutil.cc` 依赖 OpenSSL 的 `MD5()`，而 iOS 无 libcrypto；`XLogBridge.mm` 里用 CommonCrypto 的 `CC_MD5` 提供了一个 `MD5` shim。
- 插件要求关闭 Flutter 的 Swift Package Manager：`flutter config --no-enable-swift-package-manager`。

#### 重新编译 mars.xcframework

```bash
bash native/build_ios.sh
```

脚本用本地 `native/mars/` 源码、cmake 编译出含真机 + 模拟器切片的 `mars.xcframework`
并拷到 `ios/Frameworks/`。需要 `cmake / Xcode / python3`。

#### 在真机上运行（需要你的 Apple 账号）

`flutter create` 生成的工程默认 bundle id 是 `com.example.xlogPluginExample`，签名需你本人配置：

1. `open example/ios/Runner.xcworkspace`
2. 选中 **Runner** target → **Signing & Capabilities**：登录你的 Apple ID、选择 Team，必要时把 Bundle Identifier 改成唯一值
3. `cd example && flutter run -d <iPhone>`

## 目录结构

```
packages/xlog_plugin/
├── lib/
│   ├── xlog_plugin.dart        # 导出
│   └── src/
│       ├── xlog.dart           # Dart API + 上传逻辑
│       ├── xlog_level.dart
│       └── xlog_file.dart
├── android/                    # Kotlin 胶水 + vendored .so/Java (mars @ 6aa5b56)
├── ios/                        # Swift 胶水 + ObjC++ 桥接 + podspec
├── example/                    # 含开发者模式上传页
└── test/
```

## MethodChannel

所有平台统一使用 channel 名 `com.youfi/xlog_plugin`。
