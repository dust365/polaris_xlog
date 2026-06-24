# Third-Party Notices

`polaris_xlog` bundles prebuilt binaries and/or source derived from the following
projects. See each project for full license text.

## Tencent mars / mars-xlog

- **Project**: https://github.com/Tencent/mars
- **Pinned commit**: `6aa5b56` (see `native/MARS_VERSION`)
- **Usage**: Core logging engine (`libmarsxlog.so` on Android, static `mars`
  library in `mars.xcframework` on iOS)
- **License**: BSD-style (see mars repository `LICENSE`)

## zstd (via mars)

- **Project**: https://github.com/facebook/zstd
- **Usage**: Linked as part of mars xlog (compression support in mars; plugin
  default compress mode is zlib for Dart decoder compatibility)
- **License**: BSD License (see `native/mars/zstd/LICENSE` when building from source)

## micro-ecc (via mars xlog crypto)

- **Project**: https://github.com/kmackay/micro-ecc
- **Usage**: Optional log encryption helpers inside mars
- **License**: BSD 2-Clause (see mars `xlog/crypt/micro-ecc-master/LICENSE.txt`)

## Boost (via mars)

- **Usage**: mars comm / xlog C++ dependencies (header-only subsets vendored in mars)
- **License**: Boost Software License 1.0
