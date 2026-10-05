Pod::Spec.new do |s|
  s.name             = 'expiry_native_ios'
  s.version          = '1.0.0'
  s.summary          = 'Native iOS channels for the expiry label manager'
  s.description      = <<-DESC
MethodChannel implementations backed by the SUPVAN T50 Pro iOS SDK
(SFPrintSDK.xcframework), plus UserDefaults and Files-app PDF saving.
                       DESC
  s.homepage         = 'https://example.invalid/expiry_manager'
  s.license          = { :type => 'MIT' }
  s.author           = { 'xiaoqi' => 'dev@local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.static_framework = true
  s.vendored_frameworks = 'SFPrintSDK.xcframework'
  s.frameworks       = 'CoreBluetooth', 'UIKit', 'CoreGraphics'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
  }
end
