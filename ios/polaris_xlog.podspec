Pod::Spec.new do |s|
  s.name             = 'polaris_xlog'
  s.version          = '0.2.1' # keep in sync with pubspec.yaml
  s.summary          = 'Flutter plugin wrapping Tencent mars-xlog.'
  s.description      = 'High-performance daily-rotated logging powered by Tencent mars-xlog.'
  s.homepage         = 'https://github.com/dust365/polaris_xlog'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'youfi' => 'huichen@youfi.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  # --- mars-xlog ---------------------------------------------------------
  # Tencent mars xlog is not on the CocoaPods trunk and ships no prebuilt
  # binary, so we vendor an .xcframework built from source via
  # native/build_ios.sh. Device-only arm64 slice (no simulator; smaller binary).
  s.vendored_frameworks = 'Frameworks/mars.xcframework'
  s.libraries = 'z', 'c++'
  # -----------------------------------------------------------------------

  # Aligned with YouFi Runner (IPHONEOS_DEPLOYMENT_TARGET = 13.0).
  s.platform = :ios, '13.0'
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
