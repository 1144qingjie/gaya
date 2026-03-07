Pod::Spec.new do |s|
  sdk_root = '../numberAuthSDK_APP_iOS_v2.14.14_operator_ui_log_static/SDK/xcframeworks'

  s.name         = 'ATAuthSDK'
  s.version      = '2.14.14'
  s.summary      = 'Alibaba Cloud PNVS SDK for iOS'
  s.homepage     = 'https://dypns.console.aliyun.com/'
  s.license      = { :type => 'Commercial' }
  s.author       = 'Alibaba Cloud'
  s.platform     = :ios, '12.0'
  s.source       = { :path => '.' }

  s.vendored_frameworks = [
    "#{sdk_root}/ATAuthSDK.xcframework",
    "#{sdk_root}/YTXMonitor.xcframework",
    "#{sdk_root}/YTXOperators.xcframework"
  ]
  s.frameworks   = 'Network'
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC'
  }
end
