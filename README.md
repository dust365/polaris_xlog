# polaris_xlog

基于腾讯 [mars-xlog](https://github.com/Tencent/mars) 的 Flutter 高性能本地日志插件。

- **按天滚动**：`<prefix>_YYYYMMDD.xlog`，可配置 `cacheDays` 清理旧文件
- **mmap 缓冲 + 异步落盘**：写日志几乎即时返回，不阻塞 UI
- **FFI 热路径**（0.2.0+）：`v/d/i/w/e`、`flush`、`setLevel`、`close` 经 `dart:ffi` 直调原生，支持**任意 isolate** 打日志
- **可选落盘加密**：传入 ECDH `pubKey`（hex）；默认不加密，便于 App 内解码
- **纯 Dart 解码器**：设备端查看 zlib、无加密日志（上限 10 MiB）
- **无 Java mars 胶水**：Android 不含 `com.tencent.mars.*`，R8/ProGuard 无需额外 keep 规则

> **当前版本：`0.2.1`** · mars 源码 pin：`6aa5b56` · 包名：`polaris_xlog` · MethodChannel：`com.polaris.xlog`

| 链接 | |
|------|--|
| 仓库 | https://github.com/dust365/polaris_xlog |
| 问题反馈 | https://github.com/dust365/polaris_xlog/issues |
| 示例 App | [`example/`](example/)（日志查看 + 上传演示） |
| 原生重建 | [`native/README.md`](native/README.md)（维护者用，不随 pub 包分发 `native/mars/`） |

---

## 平台支持（接入前必读）

| 平台 | 支持 | 约束 |
|------|------|------|
| Android 真机 | ✅ | **仅 arm64-v8a**，minSdk **21** |
| Android 模拟器 (x86/x86_64) | ❌ | 未 vendored 对应 ABI 的 `.so` |
| iOS 真机 | ✅ | **仅 arm64**，iOS **13+** |
| iOS 模拟器 | ❌ | `mars.xcframework` 无 simulator slice |

插件走 FFI 且**无 fallback**：若 App 打进不支持的 ABI/平台，加载原生库会直接失败。请用 **arm64 真机** 开发与验收。

---

## 快速开始

### 1. 添加依赖

```bash
flutter pub add polaris_xlog
```

或 `pubspec.yaml`：

```yaml
dependencies:
  polaris_xlog: ^0.2.1
```

```bash
flutter pub get
```

### 2. Android：`abiFilters`（必须）

`android/app/build.gradle.kts`：

```kotlin
android {
    defaultConfig {
        minSdk = 21
        ndk {
            abiFilters += "arm64-v8a"
        }
    }
}
```

Groovy：`ndk { abiFilters 'arm64-v8a' }`。日志目录默认 `filesDir/xlog`，无需存储权限。

### 3. iOS：真机 + Deployment Target

- `ios/Podfile`：`platform :ios, '13.0'`
- 仅在真机构建/运行：`flutter run -d <iPhone>`
- 首次或更新插件后：`cd ios && pod install`

### 4. 初始化并写日志

```dart
import 'package:flutter/foundation.dart';
import 'package:polaris_xlog/polaris_xlog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await XLog.init(
    level: XLogLevel.info,
    namePrefix: 'myapp',          // -> myapp_YYYYMMDD.xlog
    cacheDays: 7,
    consoleLogOpen: kDebugMode,   // Debug 时同步打 logcat / Xcode
    // pubKey: '<hex ECDH 公钥>',  // 可选加密；开启后 App 内解码不可用
  );

  XLog.i('App', 'started');
  runApp(const MyApp());
}
```

```dart
XLog.v('Tag', 'verbose');
XLog.d('Tag', 'debug');
XLog.i('Tag', 'info');
XLog.w('Tag', 'warn');
XLog.e('Tag', 'error', error: e, stackTrace: s);

// 任意 isolate（0.2.0+）
await compute((_) => XLog.i('Worker', 'OK'), null);

await XLog.setLevel(XLogLevel.warn);  // 全 isolate 生效
await XLog.flush(sync: true);         // 读/上传前刷盘
await XLog.close();                   // 退出前关闭
```

---

## 架构概览

```
你的 App (Dart)
  └─ XLog (package:polaris_xlog/polaris_xlog.dart)
       ├─ init / getLogDir / listLogFiles ──► MethodChannel (com.polaris.xlog) ──► 沙盒路径   冷路径
       └─ v/d/i/w/e / setLevel / flush / close ──► dart:ffi (xlog_ffi_*) ──► mars-xlog     热路径
```

| | MethodChannel (0.1.x) | FFI (0.2.0+) |
|---|---|---|
| 单条开销 | 序列化 + 跨线程投递 | 一次 C 函数调用 |
| 调用 isolate | 仅主 isolate | **任意 isolate** |
| 阻塞 UI | 可能 | 否（mmap + mars 异步线程） |

**设计要点：**

- `init` 在 channel 侧解析沙盒目录，在 FFI 侧 `xlog_ffi_open` 打开 appender；热路径与冷路径驱动**同一个**进程级 appender。
- 级别过滤在 native（`xlog_ffi_is_enabled`），跨 isolate 行为一致。
- 原生库加载失败为**致命错误**（首次 FFI 调用抛异常），不静默降级。
- 默认 **zlib** 压缩，与内置纯 Dart 解码器兼容。

### 原生产物

| 平台 | 路径 | 说明 |
|------|------|------|
| Android | `jniLibs/arm64-v8a/libmarsxlog.so` (~748 KB) | FFI 壳 `xlog_ffi_*` 编进此 `.so` |
| iOS | `Frameworks/mars.xcframework` (~2.1 MB) | mars 静态库；FFI 壳在插件动态 framework 内，`DynamicLibrary.process()` 取符号 |

---

## 集成详解

### Android

- 插件已 vendored `libmarsxlog.so`，接入方**无需 NDK 编译**。
- `System.loadLibrary` 与 `DynamicLibrary.open('libmarsxlog.so')` 共用同一 `.so`（dlopen 引用计数）。
- **R8 / ProGuard**：无需任何 `com.tencent.mars.*` keep 规则（插件不 ship Java mars 类）。
- Flutter `--obfuscate` 只混淆 Dart，不影响 FFI 符号。

### iOS

- `mars.xcframework` 由 CocoaPods `vendored_frameworks` 引入；FFI 符号在插件 framework 内。
- 模拟器不可用；链接异常时：`flutter clean && rm -rf ios/Pods ios/Podfile.lock && flutter pub get && cd ios && pod install`。

### 列出 / 上传日志

插件**不内置 HTTP**；只提供路径，上传由业务实现：

```dart
await XLog.flush(sync: true);
final dir = await XLog.getLogDir();
final files = await XLog.listLogFiles();   // 按日期倒序
final today = await XLog.logFileForDate();
// 用 dio / http 上传 today?.path
```

参考 [`example/lib/developer_log_page.dart`](example/lib/developer_log_page.dart)。

### App 内解码

```dart
final text = await XLog.decodeLogFile(file.path);
```

- 仅支持**无 `pubKey` 的 zlib** 块；加密 / zstd 块会标注跳过。
- 上限 **10 MiB**（`XLogDecoder.maxDecodeFileBytes`），超出抛 `XLogDecodeFileTooLargeException`。

---

## API 速查

| 方法 | 通道 | 说明 |
|------|------|------|
| `XLog.init({level, namePrefix, cacheDays, consoleLogOpen, pubKey, defaultTag})` | channel + FFI | 解析目录并打开当天 appender |
| `XLog.v/d/i/w/e(tag, msg)` | **FFI** | 写日志（任意 isolate） |
| `XLog.setLevel(level)` | **FFI** | 运行时调级别 |
| `XLog.flush({sync})` | **FFI** | 刷盘 |
| `XLog.close()` | **FFI** | 刷盘并关闭 |
| `XLog.getLogDir()` | channel | 日志目录 |
| `XLog.listLogFiles()` | channel | 列出 `.xlog` |
| `XLog.logFileForDate([date])` | channel | 指定日期文件 |
| `XLog.decodeLogFile(path)` | 纯 Dart | 设备端解码 |
| `XLog.isInitialized` | — | 当前 isolate 是否已 `init` |

---

## 验证集成

1. **真机**运行（iOS 真机 / arm64 Android）。
2. 写几条日志 → `await XLog.flush(sync: true)`。
3. `getLogDir()` / `listLogFiles()` 能看到 `<prefix>_YYYYMMDD.xlog`。
4. `decodeLogFile()` 能读到内容；`consoleLogOpen: true` 时 logcat / Xcode 有输出。

可选：检查 FFI 符号

```bash
llvm-nm -D android/src/main/jniLibs/arm64-v8a/libmarsxlog.so | grep xlog_ffi
nm -gU build/ios/iphoneos/Runner.app/Frameworks/polaris_xlog.framework/polaris_xlog | grep xlog_ffi
```

---

## 常见问题

**Q：Android 混淆会有问题吗？**  
A：不会。无 `com.tencent.mars.*` Java 类，全部经 FFI，无需 ProGuard 规则。

**Q：`couldn't find "libmarsxlog.so"`？**  
A：App 打进了非 arm64 ABI 或 32 位设备。加 `abiFilters 'arm64-v8a'` 并用 arm64 真机。

**Q：iOS 模拟器编译/运行失败？**  
A：不支持模拟器，请用真机。

**Q：开了 `pubKey` 后 `decodeLogFile` 没内容？**  
A：预期行为；加密日志需服务端或官方 Python 解码器。

**Q：能自定义日志目录吗？**  
A：当前固定沙盒内（Android `filesDir/xlog`、iOS `Documents/xlog`）。

---

## 维护者：原生重建与发版

### 重建原生产物

```bash
bash native/fetch_mars.sh          # 仅首次或升级 MARS_VERSION 时
bash native/build_android.sh       # -> android/src/main/jniLibs/
bash native/build_ios.sh           # -> ios/Frameworks/mars.xcframework
```

详见 [`native/README.md`](native/README.md)。FFI 壳：`native/src/xlog_ffi.cc`（Android）与 `ios/Classes/xlog_ffi.mm`（iOS），`extern "C"` 接口须保持一致。

### 发布到 pub.dev 检查清单

1. **版本号**：`pubspec.yaml` 与 `CHANGELOG.md` 对齐（如 `0.2.0`）。
2. **提交干净工作区**：`git status` 无未提交改动（`flutter pub publish` 会警告）。
3. **Git LFS**：`.so` / `mars.xcframework` 已用 LFS 跟踪（见 [`.gitattributes`](.gitattributes)）；克隆方需 `git lfs install`。
4. **质量门禁**：
   ```bash
   flutter analyze
   flutter test
   flutter pub publish --dry-run
   ```
5. **打 tag 并发布**：
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   flutter pub publish
   ```
6. **GitHub Release**：附变更说明，方便查看版本记录。
7. **验收**：example 在 iOS 真机 + Android arm64 真机回归 `init`、写日志、`listLogFiles`、`decodeLogFile`。

---

## 许可

- 本插件：**MIT** — [LICENSE](LICENSE)
- 内置 mars-xlog 及第三方组件 — [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
