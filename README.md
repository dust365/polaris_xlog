# xlog_plugin

基于腾讯 [mars-xlog](https://github.com/Tencent/mars) 的高性能 Flutter 日志插件：按天滚动的本地日志、mmap 缓冲 + 异步落盘、可选加密、内置纯 Dart 解码器。0.2.0 起热路径改用 **`dart:ffi`**，支撑高并发写入并可在**任意 isolate** 打日志。

> 当前版本：`0.2.0-dev`。原生产物基于 mars master `6aa5b56` 源码编译。

---

# 第一部分 · 设计方案

## 1. 架构总览

插件采用 **「FFI 热路径 + MethodChannel 冷路径」混合架构**：

```
你的 App (Dart)
  └─ XLog (package:xlog_plugin)
       ├─ init / getLogDir / listLogFiles ──► MethodChannel ──► 原生(取沙盒目录)   冷路径
       └─ v/d/i/w/e / setLevel / flush / close ──► dart:ffi ──► mars-xlog          热路径
```

- **热路径走 FFI**：写日志在**调用方 isolate 上同步直写**原生，不经平台通道、不阻塞 UI 线程、无跨 isolate 拷贝。
- **冷路径走 channel**：`init` 需要 App 沙盒目录（由原生解析）、`listLogFiles/getLogDir` 是低频操作，留在 MethodChannel。
- 两条路径驱动 mars 的**同一个进程级全局 appender**：`init` 在 channel 侧打开它，日志在 FFI 侧写它，互通无碍。

## 2. 为什么用 FFI

MethodChannel 每条日志都要做一次平台通道的序列化 + 跨线程消息投递，高频写入（如 1000+ 条/秒）会成为 UI isolate 的瓶颈，且**只能在主 isolate 调用**（需要 `RootIsolateToken`）。FFI 直调把这两点都解决了：

| | MethodChannel(0.1.0) | FFI(0.2.0) |
|---|---|---|
| 单条开销 | 序列化 + 跨线程投递 | 一次 C 函数调用 |
| 调用 isolate | 仅主 isolate | **任意 isolate** |
| 阻塞 UI | 可能 | 否（mmap + 异步线程） |

## 3. 关键设计决策

- **单条直调，不做 Dart 侧批量/背压**：数据直接进 mars 的 mmap 缓冲，压缩与落盘由 mars 自己的异步线程负责；突发由 mmap 吸收，插件层不重复造队列。
- **级别过滤交给 native**：`_write` 调用 native `xlog_ffi_is_enabled()`（读一个全局 int，极快）判断是否要写。这样**跨所有 isolate 一致**——后台 isolate 即便没调过 `init/setLevel`，过滤行为也正确（不会被 Dart 侧 per-isolate 缓存误杀）。
- **每 isolate 复用 scratch buffer**：tag/msg 编码进一块按需扩容的 native 缓冲并复用，避免每条日志 `malloc/free`；isolate 退出时随其堆释放。
- **无 fallback**：原生库加载失败按**致命错误**处理（首次写日志时抛异常），不静默降级到 channel，避免“以为在写其实没写”。
- **生命周期透传 mars**：`open` 幂等、`close` 加锁 + 延迟释放、关闭后写入经 guard 直接返回不崩；插件层不自建门闩，仅保留 `isInitialized` 作 UI 提示。
- **加密参数双端对齐**：`pubKey` 在 Android / iOS 都会真正传入 mars 配置（默认空 = 不加密）。

## 4. 原生产物形态

| 平台 | 产物 | 说明 |
|------|------|------|
| Android | `jniLibs/arm64-v8a/libmarsxlog.so`（~747 KB） | FFI 壳(`xlog_ffi_*`)并进此 `.so`，Dart 用 `DynamicLibrary.open` 加载 |
| iOS | `Frameworks/mars.xcframework`（静态，~2.2 MB） | FFI 壳编进插件**自有的动态 `xlog_plugin.framework`**（CocoaPods 必 embed），mars 静态链入其中，Dart 用 `DynamicLibrary.process()` 取符号 |

> iOS 选择「mars 静态 + 壳进插件动态 framework」而非把 mars 改成动态库，是因为后者在 CocoaPods 下有编译期链接顺序与 embed 的坑；当前方案天然免 dead-strip、无需接入方手配。

## 5. 日志格式与解码

- 文件名：`<prefix>_YYYYMMDD.xlog`，**按自然日滚动**，旧文件按 `cacheDays` 清理。
- 默认 **zlib** 压缩（保证插件内置的纯 Dart 解码器可用）；可解 **无 `pubKey` 的 zlib 块**，加密 / zstd 块需后端或官方 Python 解码器。
- 解码在 **worker isolate**（`compute`）执行，不卡 UI；设备端解码上限 **10 MiB**，超出请上传到服务端解。

---

# 第二部分 · 集成方案

## 6. 平台支持与硬约束（务必先读）

| 平台 | 支持 | 约束 |
|------|------|------|
| Android 真机 | ✅ | **仅 arm64-v8a**，minSdk **21** |
| Android 模拟器 (x86/x86_64) | ❌ | 未 vendored 对应 ABI 的 `.so` |
| iOS 真机 | ✅ | **仅 arm64**，iOS **13+** |
| iOS 模拟器 | ❌ | xcframework 无 simulator slice |

> ⚠️ 因为走 FFI 且**无 fallback**：若 App 被打进插件没有的 ABI/平台（32 位 Android、iOS 模拟器），运行时加载原生库会直接失败。请按下文第 8、10 步限制 ABI / 用真机。

## 7. 添加依赖

`pubspec.yaml`：

```yaml
dependencies:
  # 方式一：Git 依赖（外部项目推荐）
  xlog_plugin:
    git:
      url: https://github.com/dust365/xlog_plugin.git
      ref: 0.2.0_ffi        # 或某个 tag / commit

  # 方式二：本地 path（monorepo / 同仓开发）
  # xlog_plugin:
  #   path: ../packages/xlog_plugin
```

```bash
flutter pub get
```

> 运行时依赖官方 `package:ffi`（自动拉取）；`ffigen` 仅维护者 dev 依赖，接入方无需关心。

## 8. Android 配置

原生产物（含 FFI 符号的 `libmarsxlog.so`）已 vendored 在插件内，**接入方无需配置 NDK / 编译**。只需让 App 只构建 arm64-v8a：

`android/app/build.gradle.kts`（Kotlin DSL）：

```kotlin
android {
    defaultConfig {
        minSdk = 21                       // 插件要求 ≥ 21
        ndk {
            abiFilters += "arm64-v8a"     // 关键：只打 arm64，避免缺 ABI 闪退
        }
    }
}
```

Groovy 写法：

```groovy
android {
    defaultConfig {
        minSdkVersion 21
        ndk { abiFilters 'arm64-v8a' }
    }
}
```

- 日志默认写在 `context.filesDir/xlog`（沙盒内，无需任何存储权限）。
- `System.loadLibrary` 与 FFI 的 `DynamicLibrary.open` 共用同一个 `.so`（dlopen 引用计数，安全）。

### 8.1 混淆 / R8 配置（重要）

`libmarsxlog.so` 通过 **JNI 按精确类名、方法名、字段名**回调 Java 层的 `com.tencent.mars.xlog.*`（如 `XLogConfig` 的字段、`Xlog` 的 native 方法）。一旦被 R8/ProGuard 改名或裁剪，运行时会 `UnsatisfiedLinkError` 或配置静默失效。

**好消息：插件已自带 consumer 混淆规则**（`android/consumer-rules.pro`，通过 `consumerProguardFiles` 自动并入接入方的混淆配置），**默认情况下你无需做任何事**，开启 `minifyEnabled true` 也安全。

仅当你的工程用了**自定义/激进的混淆**（如自行合并规则、关闭了 consumer rules、或用非标准混淆链路）才需要手动在 `android/app/proguard-rules.pro` 补：

```proguard
# xlog_plugin / mars-xlog：native 通过 JNI 按名访问，禁止改名或裁剪
-keep class com.tencent.mars.xlog.** { *; }
-keepclassmembers class com.tencent.mars.xlog.** { *; }
-keepclasseswithmembernames class com.tencent.mars.xlog.** {
    native <methods>;
}
-keep class com.youfi.xlog_plugin.** { *; }
```

> 如果用 Flutter 的 `--obfuscate`（混淆的是 Dart 代码，不影响 Java/JNI），无需额外配置。

## 9. iOS 配置

动态的 `xlog_plugin.framework`（FFI 符号所在）由 CocoaPods 自动 embed，mars 以静态库链入其中，**接入方无需手动配置 framework**。只需：

1. **Deployment Target ≥ 13.0**
   - `ios/Podfile` 顶部：`platform :ios, '13.0'`（或更高）。
   - Xcode → Runner target → `IPHONEOS_DEPLOYMENT_TARGET = 13.0`。
2. **只在真机运行/打包**（模拟器无 slice）：
   ```bash
   flutter run -d <你的iPhone>
   flutter build ios --release
   ```
3. Podfile 保持默认 `use_frameworks!`（Flutter 模板默认就有）。
4. 首次或拉新代码后：
   ```bash
   cd ios && pod install
   ```

> iOS 端无需混淆配置（FFI 符号在动态 framework 内、用 `__attribute__((visibility("default"))) __attribute__((used))` 标记，不会被 strip）。
>
> 若曾用旧版本构建过、遇到奇怪的链接/缓存问题，清一下再来：
> `flutter clean && rm -rf ios/Pods ios/Podfile.lock && flutter pub get && cd ios && pod install`

## 10. 初始化（必须先于写日志）

在 `main()` 里、`runApp` 之前完成：

```dart
import 'package:flutter/foundation.dart';
import 'package:xlog_plugin/xlog_plugin.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await XLog.init(
    level: XLogLevel.info,        // 最低写入级别
    namePrefix: 'myapp',          // 文件名前缀 -> myapp_YYYYMMDD.xlog
    cacheDays: 7,                 // mmap cache 保留天数（0 = 直接写日志目录）
    consoleLogOpen: kDebugMode,   // true: 同时打 logcat/Xcode；false: 仅写文件
    // pubKey: '<hex ECDH 公钥>',  // 可选：落盘加密（开启后 App 内解码不可用，需后端解）
  );

  XLog.i('App', 'started');
  runApp(const MyApp());
}
```

## 11. 写日志（支持任意 isolate）

```dart
XLog.v('Tag', 'verbose');
XLog.d('Tag', 'debug');
XLog.i('Tag', 'info');
XLog.w('Tag', 'warn');
XLog.e('Tag', 'error', error: e, stackTrace: s);  // error/stackTrace 会拼进消息
```

- **同步、即时返回**：数据进 mars 的 mmap 缓冲，压缩/落盘在 mars 自己的线程。
- **0.2.0 新增**：可直接在后台 isolate / `compute` 里调用，无需 `RootIsolateToken`：

```dart
await compute((_) {
  XLog.i('Worker', '在子 isolate 里写日志，OK');
}, null);
```

- 运行时调级别：`await XLog.setLevel(XLogLevel.warn);`（对所有 isolate 生效）。

## 12. 刷盘与关闭

```dart
await XLog.flush(sync: true);  // 读/上传文件前调用，确保当天缓冲落盘
await XLog.close();            // App 退出前调用
```

> `flush(sync: true)` 会**阻塞调用 isolate**直到写完；平时业务日志不需要手动 flush。

## 13. 列出 / 上传日志（上传由业务实现）

插件不内置 HTTP 客户端，只负责产出文件路径：

```dart
await XLog.flush(sync: true);

final dir = await XLog.getLogDir();          // .xlog 所在目录
final files = await XLog.listLogFiles();     // 所有日志文件，按日期倒序
final today = await XLog.logFileForDate();   // 今天的文件（可传 DateTime）

// 用你项目里的 dio / http 上传 today?.path
```

示例：`example/lib/developer_log_page.dart`。

## 14. App 内解码查看

```dart
final text = await XLog.decodeLogFile(file.path); // worker isolate 解码，不卡 UI
```

限制：
- 仅能解 **无 `pubKey` 的 zlib 块**（插件默认就是 zlib）；加密 / zstd 块会被标注跳过。
- 解码上限 **10 MiB**（`XLogDecoder.maxDecodeFileBytes`），超出抛 `XLogDecodeFileTooLargeException` —— 大文件请上传后在服务端看。

## 15. API 速查

| 方法 | 通道 | 说明 |
|------|------|------|
| `XLog.init({level, namePrefix, cacheDays, consoleLogOpen, pubKey, defaultTag})` | channel | 初始化并打开当天 appender |
| `XLog.v/d/i/w/e(tag, msg)` | **FFI** | 写日志（任意 isolate） |
| `XLog.setLevel(level)` | **FFI** | 运行时调级别（全 isolate 生效） |
| `XLog.flush({sync})` | **FFI** | 刷盘 |
| `XLog.close()` | **FFI** | 刷盘并关闭 |
| `XLog.getLogDir()` | channel | 日志目录 |
| `XLog.listLogFiles()` | channel | 列出 `.xlog` |
| `XLog.logFileForDate([date])` | channel | 指定日期文件 |
| `XLog.decodeLogFile(path)` | 纯 Dart | 设备端解码 |
| `XLog.isInitialized` | - | 当前 isolate 是否已初始化 |

## 16. 验证集成是否成功

1. **真机**跑起来（iOS 真机 / arm64 Android）。
2. 写几条日志后 `await XLog.flush(sync: true)`。
3. `XLog.getLogDir()` 看目录，`listLogFiles()` 能列出 `<prefix>_YYYYMMDD.xlog`。
4. `decodeLogFile()` 能看到刚写的内容。
5. `consoleLogOpen: true` 时，logcat / Xcode 控制台应同步看到日志。

排查原生符号是否就位（可选）：

```bash
# Android：插件产物里应能看到 FFI 符号
llvm-nm -D <插件>/android/src/main/jniLibs/arm64-v8a/libmarsxlog.so | grep xlog_ffi

# iOS：构建出的 App 里
nm -gU build/ios/iphoneos/Runner.app/Frameworks/xlog_plugin.framework/xlog_plugin | grep xlog_ffi
```

## 17. 常见问题（FAQ）

**Q：Android 开了混淆后一写日志就 `UnsatisfiedLinkError` / 日志没了？**
A：mars 的 JNI 类被 R8 改名了。插件已自带 consumer 规则，正常不会发生；若你用了激进/自定义混淆，按 8.1 手动补 keep 规则。

**Q：Android 装到设备上一写日志就崩 `couldn't find "libmarsxlog.so"`？**
A：App 打进了非 arm64 ABI，或装在 32 位设备上。按第 8 步加 `abiFilters 'arm64-v8a'`，并用 arm64 设备。

**Q：iOS 模拟器跑报找不到符号 / 编译失败？**
A：插件**不支持模拟器**（xcframework 仅 device arm64）。请用真机。

**Q：iOS 链接报 `Undefined symbol: mars::xlog::appender_open...`？**
A：通常是 Pods 缓存陈旧。`flutter clean && rm -rf ios/Pods ios/Podfile.lock && flutter pub get && cd ios && pod install`。

**Q：开了 `pubKey` 加密后 App 内 `decodeLogFile` 没内容？**
A：预期行为。加密日志需后端 / 官方 Python 解码器，App 内解码仅支持非加密 zlib。

**Q：能指定日志目录吗？**
A：当前固定写沙盒内（Android `filesDir/xlog`、iOS `Documents/xlog`），无需权限，便于备份与上传。

---

## 原生重建 / 升级 mars

接入方一般不需要。维护者重建原生产物见 [`native/README.md`](native/README.md)（**不在 pub 包内**）；FFI 壳源码在 `native/src/xlog_ffi.cc`（Android）与 `ios/Classes/xlog_ffi.mm`（iOS），改动需保持两者 `extern "C"` 接口一致。mars 源码 pin：`6aa5b56`。

## 许可

MIT — 见 [LICENSE](LICENSE) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 链接

- 仓库：https://github.com/dust365/xlog_plugin
- 问题反馈：https://github.com/dust365/xlog_plugin/issues
