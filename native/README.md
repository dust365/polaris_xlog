# mars native 构建（xlog_plugin 的原生产物来源）

本目录是 **Tencent mars-xlog 原生产物的唯一构建入口**。Android 与 iOS 都从
**同一份本地 mars 源码**（`native/mars/`，钉死在 `MARS_VERSION`）编译，保证两端
行为一致、可复现、离线可构建、可长期维护。

```
native/
├── MARS_VERSION        # 钉死的 mars 版本（tag 或 commit SHA），两端共用
├── _common.sh          # 公共函数：解析版本 / 拷贝本地源码 / 生成 verinfo.h
├── fetch_mars.sh       # 一次性下载并“补丁化”源码到 native/mars/（升级时才再跑）
├── mars/               # vendored、已打补丁、可直接编译的 mars 源码（已裁剪为 xlog-only）
├── build_ios.sh        # 产出 ios/Frameworks/mars.xcframework
└── build_android.sh    # 产出 android/src/main/jniLibs/<abi>/*.so + Java glue
```

> `native/mars/` 是从官方 tarball 下载后做了补丁的“可直接编译”副本：
> 1) 裁剪为 xlog-only —— 只保留 `comm`、`boot`（comm/alarm.h 依赖）、`boost`、`xlog`、
>    `zstd`（xlog 压缩依赖），删掉网络模块（stn/sdt/app/baseevent）与 openssl 的各平台
>    预编译库（仅留 1.4MB 的 `openssl/include` 头文件，并补一个上游缺失的 32 位
>    `opensslconf_android-x86.h`）；2) 换上现代 leetal `ios.toolchain.cmake`（支持
>    OS64/模拟器 arm64）；3) 关掉 `-Werror`、micro-ecc 的 arm 汇编，并自动生成
>    `comm/verinfo.h`。这些补丁逻辑都在 `fetch_mars.sh` 里，升级版本时一条命令即可重做。
>
> 构建脚本会把 mars+boost 的海量警告写入临时 `build*.log`，**只有失败时**才打印末尾，
> 避免刷爆调用方的输出缓冲。

## 版本来源（单一事实来源）

两端构建脚本都读取 `MARS_VERSION`：

```
6aa5b56
```

### 拉取的提交节点

| 项 | 值 |
|------|------|
| 仓库 | https://github.com/Tencent/mars |
| 分支 | `master` |
| commit | `6aa5b56`（Merge pull request #1363 from outman-zhou/master） |
| 日期 | 2025-09-01 |
| 末位修复 | `38d7126` fix(comm): memory over read when parse http data |

> 选用 master 上这个 commit 而非 tag：mars 的 git tag 非常陈旧（`v1.3.0` 到 master
> 之间差了 1300+ 个提交），其中包含大量 **xlog 关键修复**：mmap 越界、iOS
> `local_time_r` 崩溃、异步写线程抢不到锁、多实例异常、`xlogger_memory_dump`
> 缓冲溢出等。该 commit 是仓库目前（已基本停更）的最新节点，作为长期基线。
>
> Android 官方 Maven 制品 `com.tencent.mars:mars-xlog` 的版本号与 mars 的 git
> 体系**不一致**，无法对应到具体源码 commit。为了让两端真正用同一份源码，这里
> **Android 改为从源码编译**，不再依赖 Maven 制品。

## 输出产物的位置

### iOS（`native/build_ios.sh`）

```
ios/Frameworks/mars.xcframework/
└── ios-arm64/                       # 真机 arm64 only（不含模拟器 slice）
```

由 `ios/xlog_plugin.podspec` 的 `vendored_frameworks` 引用。

### Android（`native/build_android.sh`）

```
android/src/main/jniLibs/
└── arm64-v8a/  libmarsxlog.so   # c++_static, no libc++_shared.so

android/src/main/java/com/tencent/mars/xlog/
├── Xlog.java
└── Log.java
```

产物会被提交进仓库（iOS 的 `.xcframework` 与 Android 的 `.so` 建议用 **Git LFS**
跟踪，规则见 `.gitattributes`），这样 clone 后无需任何原生编译即可直接 `flutter run`。

## 环境要求

- 通用：`git`、`cmake`（≥ 3.5；脚本已对 mars 自带的老 zstd 注入 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`）、`python3`
- iOS：Xcode + Command Line Tools（提供 `xcodebuild`、`lipo`、`libtool`）
- Android：Android NDK **r21+**（本机已用 r28）。脚本默认取 `$ANDROID_HOME/ndk`
  下最新一个，可用 `ANDROID_NDK_HOME` 指定。
  > 注意：mars 自带的 `build_android.py` 写死了 gcc-4.9 工具链（NDK r18 起已移除），
  > 因此本目录的脚本**绕开它**，直接用现代 NDK 的 clang 驱动 cmake 编 `marsxlog` 目标。

## 使用

平时只需跑两个 build 脚本（它们直接用本地 `native/mars/`，**不联网**）：

```bash
bash native/build_ios.sh        # -> ios/Frameworks/mars.xcframework
bash native/build_android.sh    # -> android/src/main/jniLibs/<abi>/*.so + Java glue
```

只有在仓库里还没有 `native/mars/`（首次拉取仓库且没用 LFS 拿到产物）或要**升级版本**
时，才需要先下载源码：

```bash
bash native/fetch_mars.sh       # 按 MARS_VERSION 下载并补丁化到 native/mars/
```

### 调试符号开关（`MARS_STRIP`）

两端构建脚本默认 **`MARS_STRIP=1`**（strip 后提交，减小 LFS 体积）。排查 mars 原生崩溃时可临时保留符号：

```bash
MARS_STRIP=0 bash native/build_android.sh   # libmarsxlog.so ~12MB
MARS_STRIP=0 bash native/build_ios.sh       # mars static archive ~4.3MB
```

| `MARS_STRIP` | Android | iOS xcframework |
|---|---|---|
| **`1`（默认）** | strip 后 ~747KB | strip 后 ~2.1MB |
| `0` | 保留符号 ~12MB | 保留符号 ~4.3MB |

## 升级 mars 的标准流程

1. 修改 `MARS_VERSION` 为新的 tag 或 commit SHA。
2. `bash native/fetch_mars.sh` 重新下载并补丁化源码。
3. `bash native/build_ios.sh && bash native/build_android.sh` 重新产出。
4. 用 example 工程在 **iOS 真机** 和 **Android 真机（arm64）** 回归验证写日志、
   `listLogFiles()`、`decodeLogFile()`。
5. 留意 mars 大版本是否改了 `.xlog` 块格式或 `ios.toolchain.cmake`/zstd 等构建假设；
   若改了需同步更新本目录脚本与 `lib/src/xlog_decoder.dart`、后端解码脚本。
6. 提交：`native/mars/` + 产物（`.so` / `.xcframework`）+ 改动的 `MARS_VERSION`，打 tag 发版。

> 注：插件在 `XLogBridge.mm` 显式设置 `compress_mode_ = kZlib`，日志用 **zlib** 压缩
> （即便该 mars 版本已内置 zstd 能力）。因此纯 Dart 的 `xlog_decoder.dart` 仍可解码；
> 如果将来改用 zstd，需要给解码器补 zstd 解压。
