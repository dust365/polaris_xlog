#!/usr/bin/env bash
#
# Shared helpers for the mars native build scripts (build_ios.sh / build_android.sh).
# Both platforms compile the SAME pinned mars revision (see ./MARS_VERSION) so the
# Android .so and the iOS .xcframework always come from one source of truth.
set -euo pipefail

NATIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$NATIVE_DIR/.." && pwd)"

# Strip debug symbols from vendored native binaries before they land in jniLibs /
# mars.xcframework. Both build_ios.sh and build_android.sh honor this switch.
#
#   MARS_STRIP=1  (default) — smaller LFS footprint (Android: llvm-strip; iOS: strip -S).
#   MARS_STRIP=0  — keep symbols for native crash diagnosis (Android .so ~12MB).
#
# Example (keep symbols while debugging mars itself):
#   MARS_STRIP=0 bash native/build_android.sh
#   MARS_STRIP=0 bash native/build_ios.sh
: "${MARS_STRIP:=1}"
export MARS_STRIP

# Resolve the pinned mars revision. CLI arg overrides MARS_VERSION file.
mars_ref() {
  if [ "${1:-}" != "" ]; then
    echo "$1"
  else
    tr -d '[:space:]' < "$NATIVE_DIR/MARS_VERSION"
  fi
}

# Copy the vendored, build-ready mars source (native/mars) into a fresh work dir
# so builds never mutate the committed tree. Fails if it hasn't been fetched yet.
#   $1 = destination dir (will contain the inner mars/ tree directly)
stage_mars() {
  local dst="$1"
  if [ ! -d "$NATIVE_DIR/mars" ]; then
    echo "!! native/mars not found. Run native/fetch_mars.sh first." >&2
    exit 1
  fi
  mkdir -p "$dst"
  cp -R "$NATIVE_DIR/mars/." "$dst/"
}

# Copy the FFI shim (native/src/xlog_ffi.*) into a staged mars tree so the
# xlog/CMakeLists.txt `src/*.cc` glob compiles it into libxlog — and thus into
# libmarsxlog.so (Android) / mars.framework (iOS). Keeping the shim outside the
# vendored mars tree means `fetch_mars.sh` upgrades never clobber it.
#   $1 = inner mars dir (the staged copy)
copy_ffi_shim() {
  local mars="$1"
  if [ ! -f "$NATIVE_DIR/src/xlog_ffi.cc" ]; then
    echo "!! native/src/xlog_ffi.cc not found" >&2
    exit 1
  fi
  cp "$NATIVE_DIR/src/xlog_ffi.cc" "$NATIVE_DIR/src/xlog_ffi.h" "$mars/xlog/src/"
  echo ">> Injected FFI shim into $mars/xlog/src/"
}

# Clone Tencent/mars at the given ref (tag/branch or full commit SHA) into $1.
clone_mars() {
  local dst="$1" ref="$2"
  echo ">> Cloning Tencent/mars ($ref)"
  if git clone --depth 1 --branch "$ref" https://github.com/Tencent/mars.git "$dst" 2>/dev/null; then
    :
  else
    git clone https://github.com/Tencent/mars.git "$dst"
    git -C "$dst" checkout "$ref"
  fi
}

# Generate comm/verinfo.h ourselves. mars' own gen_mars_revision_file() is
# python2 code (writes a str to a 'wb' file) and crashes under python3; only this
# header is actually needed to compile, so we emit it directly.
#   $1 = inner mars dir (contains comm/), $2 = mars ref
write_verinfo() {
  local mars="$1" ref="$2" rev ts
  rev="$(git -C "$mars" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  cat > "$mars/comm/verinfo.h" <<EOF
#ifndef Mars_verinfo_h
#define Mars_verinfo_h

#define MARS_REVISION "$rev"
#define MARS_PATH "$ref"
#define MARS_URL ""
#define MARS_BUILD_TIME "$ts"
#define MARS_TAG "$ref"

#endif
EOF
}
