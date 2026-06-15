Pod::Spec.new do |s|
  s.name             = 'xlog_plugin'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin wrapping Tencent mars-xlog.'
  s.description      = 'High-performance, encrypted, daily-rotated logging with dev-mode upload.'
  s.homepage         = 'https://github.com/youfi/mlog'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'youfi' => 'huichen@youfi.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/XLogBridge.h'
  s.dependency 'Flutter'

  # --- mars-xlog ---------------------------------------------------------
  # Tencent mars xlog is not on the CocoaPods trunk and ships no prebuilt
  # binary, so we vendor a framework built from source. Currently arm64
  # **device** only (build via tools/build_mars_ios.sh). To also run on the
  # iOS simulator, build a SIMULATORARM64 slice and ship an .xcframework.
  s.vendored_frameworks = 'Frameworks/mars.framework'
  s.libraries = 'z', 'c++'
  # -----------------------------------------------------------------------

  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    # Vendored framework is arm64-only; skip arm64 simulator so device builds work.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }
  s.user_target_xcconfig = {
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }
  s.swift_version = '5.0'
end
