Pod::Spec.new do |s|
  s.name = 'duct_native'
  s.version = '0.1.0'
  s.summary = 'Duct-Tape VPN native host bridge'
  s.homepage = 'https://github.com/Adventnl/duct-tape-vpn'
  s.license = { :type => 'Apache-2.0', :file => '../../../LICENSE' }
  s.author = 'Duct-Tape VPN contributors'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.swift_version = '5.9'
  s.vendored_frameworks = 'Libraries/DuctBridge.xcframework'
  s.frameworks = 'NetworkExtension', 'Security', 'CryptoKit', 'LocalAuthentication'
end
