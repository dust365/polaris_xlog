# xlog_plugin 发布待办（Release TODO）

面向「可发布的 Flutter 插件」的收尾清单。`[ ]` 待办、`[x]` 已完成、`[?]` 待确认。
建议顺序：先确认决策（第 0 节）→ 再按优先级做。最终一起执行。

---

## 0. 待确认的决策（先拍板，影响后续做法）

**YouFi 对齐基线（2026-06，Flutter 3.44 / Dart 3.12）** — 插件 `android/build.gradle`、`podspec`、`pubspec` 已按此调整：

| 项 | YouFi | xlog_plugin（已对齐） |
|---|---|---|
| Dart SDK | `>=3.1.0 <4.0.0` | 同左 |
| Flutter | 3.44.0 | `>=3.10.0`（兼容 YouFi） |
| Android compileSdk | 36 | 36 |
| Android minSdk | 21（`flutter.minSdkVersion`） | 21 |
| Android ABI | **arm64-v8a only** | **arm64-v8a only**（`abiFilters` + `build_android.sh`） |
| iOS slices | 真机 arm64 only | 真机 arm64 only（无模拟器 slice） |
| Android NDK | 28.2.13676358 | 构建脚本用 `$ANDROID_HOME/ndk` 最新 |
| AGP / Kotlin | 8.11.1 / 2.2.20 | 由宿主 `settings.gradle.kts` 提供，插件不 pin 旧版 |
| JVM | Java 11 | Java 11 |
| iOS 最低版本 | 13.0 | 13.0 |

接入 YouFi 时在 `pubspec.yaml` 增加（路径按 monorepo 实际调整）：

```yaml
dependencies:
  xlog_plugin:
    path: ../../Documents/Claude/Projects/MLog/packages/xlog_plugin
```

- [?] **发布渠道**：决定走哪种分发方式（直接影响 LFS / `.pubignore` / 是否需要 Maven+CocoaPods 基建）
  - A. pub.dev 公开发布
  - B. 公司私有 git 依赖（`git:` + Git LFS）
  - C. 私有 pub server
  - D. 原生产物托管到 Maven + CocoaPods，pub 包只放 Dart
- [x] **Android ABI**：仅 **arm64-v8a**（`build_android.sh` + Gradle `abiFilters`）
- [x] **iOS slice**：仅 **真机 arm64**（`build_ios.sh` 去掉模拟器 slice）
- [?] **是否支持日志加密（pubKey/ECDH）**？
  - 现状：Dart `init` 收 `pubKey` 但 Android `appenderOpen` 未传（`XlogPlugin.kt:41` 注释还写着「1.2.6 无 pubKey」，已过时）。需确认 master 是否启用加密；若启用，App 内纯 Dart 解码器需补 ECDH 解密
- [?] **目标最低版本**：Android `minSdk`、iOS 最低系统版本定多少？
  - **已与 YouFi 对齐：minSdk 21 / iOS 13.0**
- [?] **元数据确认**：`homepage`/`repository` 真实 URL、包名 `com.youfi.xlog_plugin`、LICENSE 作者与邮箱是否正式

---

## 1. 体积精简（native 产物）

### 1.1 Android 改用 `c++_static`（重点，收益最大）
目标：去掉单独的 `libc++_shared.so`，C++ 运行时静态链进 `libmarsxlog.so`，自包含。
> 安全性：marsxlog 只导出 C 符号（`export.exp` 全是 `xlogger_*`），不跨 `.so` 边界传 C++ 对象，且已裁成单库，适合 static。

- [x] `native/build_android.sh`：`-DANDROID_STL=c++_static`，不再拷贝 `libc++_shared.so`；strip `libmarsxlog.so`
- [x] `android/src/main/kotlin/com/youfi/xlog_plugin/XlogPlugin.kt`：只 `loadLibrary("marsxlog")`
- [x] `android/build.gradle`：去掉 `packagingOptions { pickFirst libc++_shared }`
- [x] `build_android.sh` 拷贝 Java 后 sed 去掉 `Xlog.open()` 里的 `c++_shared` load
- [ ] 真机验证：`flutter run` Android 真机，确认写日志/`listLogFiles`/`decodeLogFile` 正常
- [x] 更新 `native/README.md` 说明改为 c++_static、产物只剩 `libmarsxlog.so`
- [ ] 体积复核：预期每 ABI ~2M（strip 后）

### 1.2 iOS strip
- [ ] `native/build_ios.sh`：对各 slice framework 二进制 strip 调试/本地符号（不影响功能，App 链接本就 dead-strip）
- [ ] 重新出 `mars.xcframework` 并真机验证
- [ ] 体积复核

### 1.3 ABI / slice 取舍（已定：YouFi 真机 only）
- [x] `build_android.sh` 仅 `arm64-v8a`
- [x] `build_ios.sh` 仅 `OS64`（无模拟器 slice）
- [x] 重新出包并提交 LFS 产物：`bash native/build_android.sh && bash native/build_ios.sh`

---

## 2. 发布元数据（pubspec）

- [ ] 按渠道处理 `publish_to`（pub.dev 发布需移除 `none`）
- [ ] 补全 `homepage` / `repository` / `issue_tracker` / `documentation`
- [ ] 确认 `version`、`description`、SDK 约束
- [ ] 确认 podspec 的 author/homepage/license 信息

---

## 3. 合规 / 法务（内置第三方源码 + 二进制，必做）

- [ ] 引入并保留 mars 的 LICENSE / NOTICE，README 注明来源仓库 + commit（`6aa5b56`）
- [ ] 汇总第三方声明 `THIRD_PARTY_NOTICES`：mars、zstd(BSD)、boost、micro-ecc、leetal ios-cmake
- [ ] 确认本插件 LICENSE（MIT）与上述声明不冲突

---

## 4. 原生产物分发方式（按第 0 节决策）

- [ ] 若 pub.dev：加 `.pubignore` 排除 `native/mars`(37M 源码)、`build/`、`*.log`、`cmake_build/`
- [ ] 若 git 依赖：`git lfs install`，确认 `.gitattributes` 规则生效、产物已真正入 LFS
- [ ] 若 Maven+CocoaPods：搭建 AAR/zip 托管 + 改 `build.gradle`/`podspec` 指向远端
- [ ] 确认发布包大小（pub.dev 上限 100MB）

---

## 5. 质量 / 工程化

- [ ] 加 `analysis_options.yaml`（启用 `flutter_lints`，并从 `^3.0.0` 升到当前版本）
- [ ] 加 `CHANGELOG.md`（pub.dev 必需）
- [ ] `test/`：补 `xlog_decoder` 单元测试（喂样本 `.xlog` 验证解码）
- [ ] CI（GitHub Actions）：`flutter analyze` + `flutter test`，可选两端构建冒烟
- [ ] 确认 `build/` 已被 git 忽略（目前已忽略）

---

## 6. API / 文档

- [ ] 公共 API 补 dartdoc 注释（提升 pub.dev 文档评分）
- [ ] `lib/xlog_plugin.dart` 确认只 export 公开 API，不泄露 `src/` 内部实现
- [ ] README：补平台支持矩阵、最低 SDK、权限说明、快速上手、上传示例（业务层实现）、已知限制（zstd 块不解码 / 加密日志需后端解）
- [ ] 清理过时注释（如 `XlogPlugin.kt:41` 的「1.2.6 无 pubKey」）

---

## 已完成（背景，供参考）

- [x] mars 源码迁移到 master `6aa5b56`（含大量 xlog 关键修复），两端从同一份 vendored 源码编译
- [x] iOS `mars.xcframework`（**真机 arm64 only**）出包成功
- [x] Android **arm64-v8a** `libmarsxlog.so` 出包成功
- [x] iOS 真机 + Android 真机运行验证通过
- [x] 移除 `dio` 依赖与插件内置上传逻辑，上传交由业务层（example 用 `package:http` 示范）
- [x] 插件零第三方 Dart 依赖；`flutter analyze` 无问题
- [x] `native/README.md` 记录提交节点、产物位置；删除常见问题节
