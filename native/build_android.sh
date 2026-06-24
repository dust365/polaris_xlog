#!/usr/bin/env bash
#
# Build Tencent mars-xlog for Android from source and vendor the artifact into
# the plugin. Produces, for each ABI:
#   android/src/main/jniLibs/<abi>/libmarsxlog.so   (C++ runtime statically linked)
#
# No Java glue is vendored: the appender is opened and driven entirely from Dart
# over FFI (the xlog_ffi_* symbols injected into libmarsxlog.so), so the plugin
# ships no com.tencent.mars.* classes and needs no JNI-by-name ProGuard rules.
#
# mars' own build_android.py hardcodes the gcc-4.9 toolchain which was removed in
# NDK r18+, so we drive cmake/clang directly against the same pinned mars source
# used by the iOS build (native/MARS_VERSION), keeping both platforms in sync.
#
# Requirements: cmake, an Android NDK (r21+). Set ANDROID_NDK_HOME to pick a
# specific NDK, otherwise the newest one under $ANDROID_HOME/ndk is used.
# Builds from the vendored native/mars source (run native/fetch_mars.sh first).
# Usage: native/build_android.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# YouFi / plugin default: arm64-v8a only (no armeabi-v7a / x86 emulators).
ABIS=(arm64-v8a)
API=21   # matches the plugin's minSdk

# --- locate NDK -------------------------------------------------------------
NDK="${ANDROID_NDK_HOME:-}"
if [ -z "$NDK" ]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  NDK="$SDK/ndk/$(ls "$SDK/ndk" | sort -V | tail -1)"
fi
[ -d "$NDK" ] || { echo "!! NDK not found ($NDK). Set ANDROID_NDK_HOME."; exit 1; }
HOST="$(ls "$NDK/toolchains/llvm/prebuilt" | head -1)"   # e.g. darwin-x86_64
STRIP="$NDK/toolchains/llvm/prebuilt/$HOST/bin/llvm-strip"
NM="$NDK/toolchains/llvm/prebuilt/$HOST/bin/llvm-nm"
echo ">> Using NDK: $NDK ($HOST)"
echo ">> ANDROID_STL=c++_static (no separate libc++_shared.so)"
echo ">> MARS_STRIP=$MARS_STRIP (0=keep debug symbols, 1=llvm-strip)"

WORK="${TMPDIR:-/tmp}/mars_android_$$"
MARS="$WORK/mars"              # build from a throwaway copy of native/mars
mkdir -p "$WORK"
stage_mars "$MARS"
copy_ffi_shim "$MARS"

# Export the FFI symbols. libmarsxlog.so is linked with a version-script
# (export.exp) whose `local: *;` hides everything not explicitly listed, so add
# the xlog_ffi_* family to the global section or Dart's dlsym would fail.
EXP="$MARS/libraries/mars_android_sdk/jni/export.exp"
if ! grep -q 'xlog_ffi_' "$EXP"; then
  awk '/^global:/ && !done {print; print "    xlog_ffi_*;"; done=1; next} {print}' \
    "$EXP" > "$EXP.tmp" && mv "$EXP.tmp" "$EXP"
  echo ">> Added xlog_ffi_* to Android export.exp"
fi

# The shim lands in libxlog.a but nothing references it, so the linker would not
# pull its object into libmarsxlog.so (and --gc-sections would drop it). Force
# each symbol as an undefined link root so the object is pulled and retained.
ROOT_CM="$MARS/CMakeLists.txt"
if ! grep -q 'xlog_ffi_log' "$ROOT_CM"; then
  UFLAGS="-Wl,-u,xlog_ffi_open -Wl,-u,xlog_ffi_set_level -Wl,-u,xlog_ffi_get_level -Wl,-u,xlog_ffi_is_enabled -Wl,-u,xlog_ffi_log -Wl,-u,xlog_ffi_flush -Wl,-u,xlog_ffi_close"
  sed -i.bak "s|-Wl,--gc-sections -Wl,--version-script|$UFLAGS -Wl,--gc-sections -Wl,--version-script|" \
    "$ROOT_CM" && rm -f "$ROOT_CM.bak"
  echo ">> Forced xlog_ffi_* link roots in marsxlog target"
fi

JNILIBS="$PLUGIN_DIR/android/src/main/jniLibs"
echo ">> Cleaning $JNILIBS"
rm -rf "$JNILIBS"

for abi in "${ABIS[@]}"; do
  echo ">> Building Android ABI $abi"
  BUILD="$MARS/cmake_build/android_$abi"
  LOG="$WORK/build_$abi.log"
  rm -rf "$BUILD"; mkdir -p "$BUILD"
  # mars+boost emit a flood of deprecation warnings; keep that out of stdout
  # (a multi-MB stream can overrun the caller's capture) and surface it only on
  # failure via the log tail.
  if ! ( cd "$BUILD" && cmake "$MARS" -G "Unix Makefiles" \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_NDK="$NDK" \
      -DANDROID_ABI="$abi" \
      -DANDROID_PLATFORM="android-$API" \
      -DANDROID_STL=c++_static \
    && cmake --build . --target marsxlog -- -j"${MARS_JOBS:-6}" ) > "$LOG" 2>&1; then
    echo "!! build failed for $abi; last 40 log lines:"; tail -40 "$LOG"; exit 1
  fi

  SO="$(find "$BUILD" -name libmarsxlog.so | head -1)"
  [ -n "$SO" ] || { echo "!! libmarsxlog.so not found for $abi"; exit 1; }
  DST="$JNILIBS/$abi"; mkdir -p "$DST"
  cp "$SO" "$DST/"
  if [ "$MARS_STRIP" = "1" ]; then
    "$STRIP" "$DST/libmarsxlog.so"
    echo "OK $abi -> $DST ($(ls -lh "$DST/libmarsxlog.so" | awk '{print $5}'), stripped)"
  else
    echo "OK $abi -> $DST ($(ls -lh "$DST/libmarsxlog.so" | awk '{print $5}'), symbols kept)"
  fi

  # Hard gate: the FFI hot path is dlsym-only, so a missing export means a
  # runtime crash with no fallback. Fail the build instead (plan §3/§11).
  missing=""
  for sym in xlog_ffi_open xlog_ffi_set_level xlog_ffi_is_enabled \
             xlog_ffi_log xlog_ffi_flush xlog_ffi_close; do
    "$NM" -D "$DST/libmarsxlog.so" 2>/dev/null | grep -q " $sym\$" || missing="$missing $sym"
  done
  if [ -n "$missing" ]; then
    echo "!! FFI symbols NOT exported from libmarsxlog.so ($abi):$missing"; exit 1
  fi
  echo ">> Verified FFI exports for $abi: xlog_ffi_*"
done

echo ">> Done. jniLibs:"
find "$JNILIBS" -name '*.so' -exec ls -la {} \;
rm -rf "$WORK"
