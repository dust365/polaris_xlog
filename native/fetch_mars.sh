#!/usr/bin/env bash
#
# Download the pinned Tencent/mars source ONCE into native/mars/ and make it
# build-ready (trim to xlog-only + apply toolchain patches + generate verinfo.h).
# After this, the per-platform build scripts compile from this local copy and
# never hit the network. Re-run this only when bumping native/MARS_VERSION.
#
# Pinned to master @ 6aa5b56 (Sep 2025) which carries many xlog fixes missing
# from the ancient v1.3.0 tag (mmap overflow, iOS local_time_r crash, async-log
# lock starvation, multi-instance, memory_dump buffer overflow, ...).
#
# Usage: native/fetch_mars.sh [mars_git_ref]   # ref defaults to native/MARS_VERSION
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

REF="$(mars_ref "${1:-}")"
DST="$NATIVE_DIR/mars"
WORK="${TMPDIR:-/tmp}/mars_fetch_$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

echo ">> Fetching Tencent/mars ($REF)"
TARBALL="$WORK/mars.tar.gz"
# GitHub serves archives for tags, branches and commit SHAs via /archive/<ref>.
if curl -fsSL "https://github.com/Tencent/mars/archive/$REF.tar.gz" -o "$TARBALL" 2>/dev/null \
   || curl -fsSL "https://github.com/Tencent/mars/archive/refs/tags/$REF.tar.gz" -o "$TARBALL" 2>/dev/null; then
  tar -xzf "$TARBALL" -C "$WORK"
  SRC="$(echo "$WORK"/mars-*/mars)"
else
  clone_mars "$WORK/clone" "$REF"
  SRC="$WORK/clone/mars"
fi
[ -d "$SRC" ] || { echo "!! could not locate inner mars/ dir"; exit 1; }

echo ">> Installing source into $DST"
rm -rf "$DST"
mkdir -p "$DST"
cp -R "$SRC/." "$DST/"
rm -rf "$DST/.git" "$DST"/cmake_build* "$DST/samples"

# --- patch for modern NDK/clang + cmake 4 -----------------------------------
# 1) drop -Werror (new clang flags many boost/STL deprecations as errors).
sed -i '' 's/-Werror=sign-compare//g; s/-Werror//g' "$DST/comm/CMakeExtraFlags.txt"
# 2) micro-ecc ARM asm uses '.syntax divided', rejected by clang's integrated-as.
sed -i '' 's|#include "asm_arm.inc"|/* asm_arm.inc disabled for clang integrated-as */|' \
  "$DST/xlog/crypt/micro-ecc-master/uECC.c"
# 3) verinfo.h: mars' generator is python2-only; emit it ourselves.
write_verinfo "$DST" "$REF"
# 4) swap in the modern leetal/ios-cmake toolchain (OS64 / SIMULATORARM64).
LEETAL_REF="4.5.0"
echo ">> Installing leetal ios-cmake toolchain ($LEETAL_REF)"
curl -fsSL "https://raw.githubusercontent.com/leetal/ios-cmake/$LEETAL_REF/ios.toolchain.cmake" \
  -o "$DST/ios.toolchain.cmake"

# 5) Trim to an xlog-only build. The xlog target needs comm + boot (comm's
#    alarm.h includes boot/context.h) + boost + xlog + zstd. Everything else
#    (networking: app/baseevent/sdt/stn) and openssl's prebuilt libs are dropped.
cat > "$DST/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required (VERSION 3.6)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}" CACHE PATH "Installation directory" FORCE)
message(STATUS "CMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}")

include_directories(openssl/include)

add_subdirectory(comm comm)
add_subdirectory(boot boot)
add_subdirectory(boost boost)
add_subdirectory(xlog xlog)

# zstd (xlog log compression)
option(ZSTD_BUILD_STATIC "BUILD STATIC LIBRARIES" ON)
option(ZSTD_BUILD_SHARED "BUILD SHARED LIBRARIES" OFF)
set(ZSTD_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/zstd")
set(LIBRARY_DIR ${ZSTD_SOURCE_DIR}/lib)
include(GNUInstallDirs)
add_subdirectory(zstd/build/cmake/lib zstd)

project (mars)

include(comm/utils.cmake)

include_directories(.)
include_directories(..)

set(SELF_LIBS_OUT ${CMAKE_SYSTEM_NAME}.out)

if(ANDROID)
    find_library(log-lib log)
    find_library(z-lib z)

    set(SELF_LIB_NAME marsxlog)
    file(GLOB SELF_SRC_FILES libraries/mars_android_sdk/jni/JNI_OnLoad.cc
            libraries/mars_xlog_sdk/jni/import.cc)
    add_library(${SELF_LIB_NAME} SHARED ${SELF_SRC_FILES})
    install(TARGETS ${SELF_LIB_NAME} LIBRARY DESTINATION ${SELF_LIBS_OUT} ARCHIVE DESTINATION ${SELF_LIBS_OUT})

    get_filename_component(EXPORT_XLOG_EXP_FILE libraries/mars_android_sdk/jni/export.exp ABSOLUTE)
    # --undefined-version: export.exp lists a few symbols absent in this build;
    # modern lld errors on that, so tolerate it (old GNU ld behaviour).
    set(SELF_XLOG_LINKER_FLAG "-Wl,--gc-sections -Wl,--version-script='${EXPORT_XLOG_EXP_FILE}' -Wl,--undefined-version")
    target_link_libraries(${SELF_LIB_NAME} "${SELF_XLOG_LINKER_FLAG}"
                            xlog mars-boost comm libzstd_static ${log-lib} ${z-lib})
endif()
CMAKE

echo ">> Trimming unused modules"
rm -rf "$DST/app" "$DST/baseevent" "$DST/sdt" "$DST/stn" \
       "$DST/lint" "$DST/uwpproj" "$DST/mars-log-mac.xcodeproj" "$DST/gradle" \
       "$DST"/*.bat "$DST/build_osx.py" "$DST/build_watch.py" \
       "$DST/build_windows.py" "$DST/build_android.py" "$DST/build_ios.py" \
       "$DST/gradlew" "$DST/gradlew.bat" "$DST/build.gradle" \
       "$DST/gradle.properties" "$DST/settings.gradle"
# openssl: keep only headers (the global include path); drop the prebuilt libs.
# comm/strutil.cc includes <openssl/...>; we don't link openssl (the symbols are
# unreferenced by xlog and dropped via --gc-sections) but the headers must parse.
find "$DST/openssl" -mindepth 1 -maxdepth 1 ! -name include -exec rm -rf {} + 2>/dev/null || true
# upstream ships no 32-bit x86 opensslconf; reuse the 32-bit arm config so the
# x86 ABI's headers resolve (header-only; nothing openssl is actually linked).
OSSL_CONF="$DST/openssl/include/openssl"
[ -f "$OSSL_CONF/opensslconf_android-x86.h" ] || \
  cp "$OSSL_CONF/opensslconf_android-arm.h" "$OSSL_CONF/opensslconf_android-x86.h" 2>/dev/null || true
# zstd: keep lib + cmake build glue; drop tests/docs/programs/etc.
( cd "$DST/zstd" && find . -mindepth 1 -maxdepth 1 \
    ! -name lib ! -name build ! -name CHANGELOG ! -name LICENSE \
    -exec rm -rf {} + 2>/dev/null ) || true

echo ">> Done. Vendored mars source ready at native/mars (ref=$REF)."
du -sh "$DST" 2>/dev/null || true
