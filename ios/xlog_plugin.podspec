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
  # Tencent mars xlog is not on the CocoaPods trunk. Pick ONE of:
  #
  # (A) Vendor a prebuilt framework (recommended). Build mars/xlog from
  #     https://github.com/Tencent/mars and drop mars.framework into
  #     ios/Frameworks/, then uncomment:
  # s.vendored_frameworks = 'Frameworks/mars.framework'
  #
  # (B) Depend on a podspec you host (git source in the example Podfile):
  s.dependency 'mars', '~> 1.2.5'
  # -----------------------------------------------------------------------

  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
  s.swift_version = '5.0'
end
