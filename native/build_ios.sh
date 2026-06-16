#!/usr/bin/env bash
#
# Build Tencent mars-xlog into ios/Frameworks/mars.xcframework from source.
#
# mars is not on the CocoaPods trunk and ships no prebuilt binary, so we compile
# it ourselves. The output .xcframework bundles three slices so the plugin runs
# on real devices AND the simulator:
#   - OS64           : iphoneos  arm64    (real device)
#   - SIMULATORARM64 : iphonesim arm64    (Apple Silicon simulator)
#   - SIMULATOR64    : iphonesim x86_64   (Intel simulator)
# The two simulator slices are lipo'd into one framework before assembly.
#
# Requirements: cmake, Xcode command line tools, python3.
# Builds from the vendored native/mars source (run native/fetch_mars.sh first).
# Usage: native/build_ios.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

WORK="${TMPDIR:-/tmp}/mars_ios_$$"
MARS="$WORK/mars"              # build from a throwaway copy of native/mars
STAGE="$WORK/stage"
mkdir -p "$WORK" "$STAGE"
stage_mars "$MARS"

PLATFORMS="OS64 SIMULATORARM64 SIMULATOR64"
STAGE="$STAGE" PLATFORMS="$PLATFORMS" python3 - "$MARS" <<'PY'
import os, glob, sys
SCRIPT = sys.argv[1]
sys.path.insert(0, SCRIPT)
from mars_utils import (libtool_libs, make_static_framework, clean,
                        XLOG_COPY_HEADER_FILES)
STAGE = os.environ['STAGE']
PLATFORMS = os.environ['PLATFORMS'].split()

os.chdir(SCRIPT)

for plat in PLATFORMS:
    print('>> Building iOS slice', plat, flush=True)
    build = 'cmake_build/%s' % plat
    out = build + '/iOS.out'
    os.chdir(SCRIPT)
    clean(build); os.makedirs(build, exist_ok=True)
    os.chdir(build)
    # cmake >= 4 dropped compat with mars' bundled zstd cmake_minimum_required.
    cmd = ('cmake ../.. -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release '
           '-DCMAKE_TOOLCHAIN_FILE=../../ios.toolchain.cmake -DPLATFORM=%s '
           '-DENABLE_ARC=0 -DENABLE_BITCODE=0 -DENABLE_VISIBILITY=1 '
           '&& make -j8 && make install') % plat
    # mars+boost emit a multi-MB warning stream; keep it in a log and only show
    # the tail on failure so the caller's output buffer never overflows.
    if os.system('( %s ) > build.log 2>&1' % cmd) != 0:
        print('!! build failed for %s; last 40 log lines:' % plat, flush=True)
        os.system('tail -40 build.log')
        sys.exit(1)
    os.chdir(SCRIPT)
    libs = [out + '/libcomm.a', out + '/libmars-boost.a', out + '/libxlog.a']
    # xlog on this mars revision compresses with zstd -> bundle libzstd_static.a
    # (older revisions used zlib and shipped no zstd lib, hence the fallback).
    zstd = (glob.glob(build + '/**/libzstd_static.a', recursive=True)
            + glob.glob(build + '/**/libzstd.a', recursive=True))
    if zstd:
        libs.append(zstd[0])
    assert libtool_libs(libs, out + '/mars'), 'libtool failed for %s' % plat
    make_static_framework(out + '/mars', out + '/mars.framework', XLOG_COPY_HEADER_FILES, '../')
    dst = os.path.join(STAGE, plat)
    os.makedirs(dst, exist_ok=True)
    os.system('cp -R "%s" "%s/"' % (out + '/mars.framework', dst))
    print('OK iOS slice', plat, flush=True)
PY

echo ">> Combining simulator slices (arm64 + x86_64)"
SIM_FW="$STAGE/SIMULATOR/mars.framework"
mkdir -p "$STAGE/SIMULATOR"
cp -R "$STAGE/SIMULATORARM64/mars.framework" "$STAGE/SIMULATOR/"
lipo -create \
  "$STAGE/SIMULATORARM64/mars.framework/mars" \
  "$STAGE/SIMULATOR64/mars.framework/mars" \
  -output "$SIM_FW/mars"
lipo -info "$SIM_FW/mars"

DST="$PLUGIN_DIR/ios/Frameworks"
echo ">> Assembling mars.xcframework into $DST"
mkdir -p "$DST"
rm -rf "$DST/mars.xcframework" "$DST/mars.framework"
xcodebuild -create-xcframework \
  -framework "$STAGE/OS64/mars.framework" \
  -framework "$SIM_FW" \
  -output "$DST/mars.xcframework"

echo ">> Done. Slices:"
find "$DST/mars.xcframework" -name mars -maxdepth 3 -exec lipo -info {} \;
rm -rf "$WORK"
