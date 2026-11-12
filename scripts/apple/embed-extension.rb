#!/usr/bin/env ruby
# Requires the same xcodeproj gem used by CocoaPods. Run on the intended Apple build host.
require 'xcodeproj'
require 'fileutils'
require 'pathname'
platform, bundle = ARGV
abort 'Usage: embed-extension.rb ios|macos your.provisioned.bundle.id' unless %w[ios macos].include?(platform) && bundle&.match?(/\A[A-Za-z0-9.-]+\z/)
repo = File.expand_path('../..', __dir__)
project_path = File.join(repo, 'clients/app', platform, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'
abort 'PacketTunnel target exists; preserve and inspect it' if project.targets.any? { |t| t.name == 'PacketTunnel' }
FileUtils.cp_r(project_path, project_path + '.before-dtvpn') unless File.exist?(project_path + '.before-dtvpn')
packet = project.new_target(:app_extension, 'PacketTunnel', platform == 'ios' ? :ios : :osx, platform == 'ios' ? '15.0' : '12.0')
group = project.main_group.new_group('DuctPacketTunnel')
source = File.join(repo, 'clients/native/apple')
relative_source = Pathname.new(source).relative_path_from(Pathname.new(File.dirname(project_path))).to_s
['PacketTunnel/PacketTunnelProvider.swift', 'Sources/SecureStore.swift'].each do |file|
  packet.add_file_references([group.new_file(File.join(relative_source, file))])
end
package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package.repositoryURL = 'https://github.com/WireGuard/wireguard-apple.git'
package.requirement = {'kind' => 'revision', 'revision' => '2fec12a6e1f6e3460b6ee483aa00ad29cddadab1'}
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = package
product.product_name = 'WireGuardKit'
packet.package_product_dependencies << product
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
packet.frameworks_build_phase.files << build_file
packet.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle + '.PacketTunnel'
  c.build_settings['INFOPLIST_FILE'] = File.join(relative_source, 'PacketTunnel/Info.plist')
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/PacketTunnel.entitlements'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  c.build_settings['SKIP_INSTALL'] = 'YES'
  c.build_settings['MARKETING_VERSION'] = '0.1.0'
  c.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  c.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
  c.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
  c.build_settings['LIBRARY_SEARCH_PATHS'] = ['$(inherited)', '$(CONFIGURATION_BUILD_DIR)']
end
runner.add_dependency(packet)
embed = runner.new_copy_files_build_phase('Embed Duct Packet Tunnel')
embed.dst_subfolder_spec = '13'
ref = embed.add_file_reference(packet.product_reference)
ref.settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}
phase = packet.new_shell_script_build_phase('Build official WireGuard Go library')
phase.shell_script = "set -eu\ncd \"${SRCROOT}/../../../.local/wireguard-apple/Sources/WireGuardKitGo\"\n/usr/bin/make\n"
phase.always_out_of_date = '1'
packet.build_phases.delete(phase)
packet.build_phases.unshift(phase)
# Preserve Flutter's Debug JIT/server rights when adding VPN and Keychain rights.
# iOS must not receive macOS-only sandbox entitlements.
rights = {
  'com.apple.developer.networking.networkextension' => ['packet-tunnel-provider'],
  'keychain-access-groups' => ['$(AppIdentifierPrefix)dev.ducttape.shared']
}
rights.merge!('com.apple.security.app-sandbox' => true, 'com.apple.security.network.client' => true) if platform == 'macos'
host = File.dirname(project_path)
Xcodeproj::Plist.write_to_path(rights, File.join(host, 'Runner/PacketTunnel.entitlements'))
info_path = File.join(host, 'Runner/Info.plist')
info = Xcodeproj::Plist.read_from_path(info_path)
info['DuctKeychainGroup'] = '$(AppIdentifierPrefix)dev.ducttape.shared'
Xcodeproj::Plist.write_to_path(info, info_path)
runner.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle
  c.build_settings[platform == 'ios' ? 'IPHONEOS_DEPLOYMENT_TARGET' : 'MACOSX_DEPLOYMENT_TARGET'] = platform == 'ios' ? '15.0' : '12.0'
  current = c.build_settings['CODE_SIGN_ENTITLEMENTS']
  entitlements = current ? Xcodeproj::Plist.read_from_path(File.join(host, current)) : {}
  entitlements.merge!(rights)
  destination = "Runner/DuctRunner-#{c.name}.entitlements"
  Xcodeproj::Plist.write_to_path(entitlements, File.join(host, destination))
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = destination
end
project.save
puts 'Runner and packet extension configured. Supply legitimate profiles and DEVELOPMENT_TEAM privately before installing. No signing identity was supplied or selected.'
