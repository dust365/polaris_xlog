#!/usr/bin/env bash
#
# Build Tencent mars-xlog for Android from source and vendor the artifacts into
# the plugin. Produces, for each ABI:
#   android/src/main/jniLibs/<abi>/libmarsxlog.so   (C++ runtime statically linked)
# plus the Java glue classes:
#   android/src/main/java/com/tencent/mars/xlog/{Xlog,Log}.java
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
echo ">> Using NDK: $NDK ($HOST)"
echo ">> ANDROID_STL=c++_static (no separate libc++_shared.so)"
echo ">> MARS_STRIP=$MARS_STRIP (0=keep debug symbols, 1=llvm-strip)"

WORK="${TMPDIR:-/tmp}/mars_android_$$"
MARS="$WORK/mars"              # build from a throwaway copy of native/mars
mkdir -p "$WORK"
stage_mars "$MARS"

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
done

# --- vendor the Java glue (so we can drop the Maven dependency) --------------
JAVA_SRC="$MARS/libraries/mars_xlog_sdk/src/main/java/com/tencent/mars/xlog"
JAVA_DST="$PLUGIN_DIR/android/src/main/java/com/tencent/mars/xlog"
mkdir -p "$JAVA_DST"
cp "$JAVA_SRC/Xlog.java" "$JAVA_SRC/Log.java" "$JAVA_DST/"
# c++_static: drop the separate libc++_shared load from upstream Xlog.open().
sed -i '' '/System.loadLibrary("c++_shared")/d' "$JAVA_DST/Xlog.java" 2>/dev/null \
  || sed -i '/System.loadLibrary("c++_shared")/d' "$JAVA_DST/Xlog.java"
echo ">> Vendored Java glue into $JAVA_DST"

echo ">> Done. jniLibs:"
find "$JNILIBS" -name '*.so' -exec ls -la {} \;
rm -rf "$WORK"
