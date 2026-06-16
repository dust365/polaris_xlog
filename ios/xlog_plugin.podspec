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
  # binary, so we vendor an .xcframework built from source via
  # native/build_ios.sh. It bundles device (arm64) and simulator
  # (arm64 + x86_64) slices, so it runs on real devices and the simulator.
  s.vendored_frameworks = 'Frameworks/mars.xcframework'
  s.libraries = 'z', 'c++'
  # -----------------------------------------------------------------------

  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
  s.user_target_xcconfig = {
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
  s.swift_version = '5.0'
end
