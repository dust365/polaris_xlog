#!/usr/bin/env bash
#
# Build Tencent mars-xlog into ios/Frameworks/mars.framework (arm64 device).
#
# mars is not on CocoaPods and ships no prebuilt binary, so we compile it from
# source. This produces a static framework for the iOS device (arm64) that the
# plugin vendors. To also support the iOS simulator on Apple Silicon, build a
# SIMULATORARM64 slice too and combine into an .xcframework.
#
# Requirements: git, cmake, Xcode command line tools, python3.
# Usage: tools/build_mars_ios.sh [mars_git_ref]
set -euo pipefail

MARS_REF="${1:-master}"
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/mars_build_$$"
MARS="$WORK/mars/mars"

echo ">> Cloning Tencent/mars ($MARS_REF) into $WORK"
mkdir -p "$WORK"
git clone --depth 1 --branch "$MARS_REF" https://github.com/Tencent/mars.git "$WORK/mars" 2>/dev/null \
  || git clone --depth 1 https://github.com/Tencent/mars.git "$WORK/mars"

cd "$MARS"

# cmake >= 4 dropped compatibility with the very old cmake_minimum_required in
# mars' bundled zstd; allow it explicitly.
BUILD=cmake_build/iOS
OUT="$BUILD/iOS.out"

python3 - "$MARS" <<'PY'
import os, glob, sys
sys.path.insert(0, sys.argv[1])
from mars_utils import gen_mars_revision_file, libtool_libs, make_static_framework, clean, XLOG_COPY_HEADER_FILES
SCRIPT = sys.argv[1]; BUILD='cmake_build/iOS'; OUT=BUILD+'/iOS.out'
os.chdir(SCRIPT)
gen_mars_revision_file('comm')
clean(BUILD); os.makedirs(BUILD, exist_ok=True); os.chdir(BUILD)
cmd=('cmake ../.. -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release '
     '-DCMAKE_TOOLCHAIN_FILE=../../ios.toolchain.cmake -DPLATFORM=OS64 '
     '-DENABLE_ARC=0 -DENABLE_BITCODE=0 -DENABLE_VISIBILITY=1 && make -j8 && make install')
assert os.system(cmd)==0, 'cmake/make failed'
os.chdir(SCRIPT)
zstd=glob.glob(OUT+'/libzstd.a')+glob.glob(BUILD+'/zstd/libzstd.a')+glob.glob(BUILD+'/lib/libzstd.a')
libs=[OUT+'/libcomm.a', OUT+'/libmars-boost.a', OUT+'/libxlog.a', zstd[0]]
assert libtool_libs(libs, OUT+'/mars'), 'libtool failed'
make_static_framework(OUT+'/mars', OUT+'/mars.framework', XLOG_COPY_HEADER_FILES, '../')
print('OK', os.path.join(SCRIPT, OUT, 'mars.framework'))
PY

DST="$PLUGIN_DIR/ios/Frameworks"
echo ">> Installing mars.framework into $DST"
mkdir -p "$DST"
rm -rf "$DST/mars.framework"
cp -R "$MARS/$OUT/mars.framework" "$DST/"
lipo -info "$DST/mars.framework/mars"
echo ">> Done. Cleaning $WORK"
rm -rf "$WORK"
