#!/usr/bin/env bash
#
# Build Tencent mars-xlog into ios/Frameworks/mars.xcframework.
#
# mars is not on CocoaPods and ships no prebuilt binary, so we compile it from
# source. This produces an .xcframework with three slices so the plugin runs on
# both real devices and the iOS simulator:
#   - OS64           : iphoneos  arm64        (real device)
#   - SIMULATORARM64 : iphonesim arm64        (Apple Silicon simulator)
#   - SIMULATOR64    : iphonesim x86_64       (Intel simulator)
# The two simulator slices are lipo'd into one framework before assembly.
#
# Requirements: git, cmake, Xcode command line tools, python3.
#
# Usage: tools/build_mars_ios.sh [mars_git_ref]
#   mars_git_ref defaults to the pinned revision below. Keep this pinned so the
#   build stays reproducible; bump it deliberately when upgrading mars.
set -euo pipefail

# Pinned mars revision. Bump deliberately and re-run; do NOT track a branch.
MARS_REF="${1:-v1.2.6}"

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/mars_build_$$"
MARS="$WORK/mars/mars"
STAGE="$WORK/stage"

echo ">> Cloning Tencent/mars ($MARS_REF) into $WORK"
mkdir -p "$WORK" "$STAGE"
git clone --depth 1 --branch "$MARS_REF" https://github.com/Tencent/mars.git "$WORK/mars" 2>/dev/null \
  || git clone --depth 1 https://github.com/Tencent/mars.git "$WORK/mars"

# Build one slice per PLATFORM into $STAGE/<PLATFORM>/mars.framework.
PLATFORMS="OS64 SIMULATORARM64 SIMULATOR64"
STAGE="$STAGE" PLATFORMS="$PLATFORMS" python3 - "$MARS" <<'PY'
import os, glob, sys
SCRIPT = sys.argv[1]
sys.path.insert(0, SCRIPT)
from mars_utils import (gen_mars_revision_file, libtool_libs,
                        make_static_framework, clean, XLOG_COPY_HEADER_FILES)
STAGE = os.environ['STAGE']
PLATFORMS = os.environ['PLATFORMS'].split()

os.chdir(SCRIPT)
gen_mars_revision_file('comm')

for plat in PLATFORMS:
    print('>> Building slice', plat, flush=True)
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
    assert os.system(cmd) == 0, 'cmake/make failed for %s' % plat
    os.chdir(SCRIPT)
    zstd = (glob.glob(out + '/libzstd.a') + glob.glob(build + '/zstd/libzstd.a')
            + glob.glob(build + '/lib/libzstd.a'))
    libs = [out + '/libcomm.a', out + '/libmars-boost.a', out + '/libxlog.a', zstd[0]]
    assert libtool_libs(libs, out + '/mars'), 'libtool failed for %s' % plat
    make_static_framework(out + '/mars', out + '/mars.framework', XLOG_COPY_HEADER_FILES, '../')
    dst = os.path.join(STAGE, plat)
    os.makedirs(dst, exist_ok=True)
    os.system('cp -R "%s" "%s/"' % (out + '/mars.framework', dst))
    print('OK slice', plat, flush=True)
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

echo ">> Done:"
find "$DST/mars.xcframework" -name mars -maxdepth 3 -exec lipo -info {} \;
echo ">> Cleaning $WORK"
rm -rf "$WORK"
