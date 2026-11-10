#!/usr/bin/env ruby
# Requires the same xcodeproj gem used by CocoaPods. Run on the intended Apple build host.
require 'xcodeproj'
require 'fileutils'
platform, bundle = ARGV
abort 'Usage: embed-extension.rb ios|macos your.provisioned.bundle.id' unless %w[ios macos].include?(platform) && bundle&.match?(/\A[A-Za-z0-9.-]+\z/)
repo = File.expand_path('../..', __dir__)
project_path = File.join(repo, 'clients/app', platform, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'
abort 'PacketTunnel target exists; preserve and inspect it' if project.targets.any? { |t| t.name == 'PacketTunnel' }
FileUtils.cp_r(project_path, project_path + '.before-dtvpn')
packet = project.new_target(:app_extension, 'PacketTunnel', platform == 'ios' ? :ios : :osx, platform == 'ios' ? '15.0' : '12.0')
group = project.main_group.new_group('DuctPacketTunnel')
source = File.join(repo, 'clients/native/apple')
['PacketTunnel/PacketTunnelProvider.swift', 'Sources/SecureStore.swift'].each do |file|
  packet.add_file_references([group.new_file(File.join(source, file))])
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
  c.build_settings['INFOPLIST_FILE'] = File.join(source, 'PacketTunnel/Info.plist')
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = File.join(source, 'PacketTunnel/PacketTunnel.entitlements')
  c.build_settings['SWIFT_VERSION'] = '5.9'
  c.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  c.build_settings['SKIP_INSTALL'] = 'YES'
  c.build_settings['LIBRARY_SEARCH_PATHS'] = ['$(inherited)', '$(CONFIGURATION_BUILD_DIR)']
end
runner.add_dependency(packet)
embed = runner.new_copy_files_build_phase('Embed Duct Packet Tunnel')
embed.dst_subfolder_spec = '13'
ref = embed.add_file_reference(packet.product_reference)
ref.settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}
phase = packet.new_shell_script_build_phase('Build official WireGuard Go library')
phase.shell_script = "set -eu\ncd #{File.join(repo, '.local/wireguard-apple/Sources/WireGuardKitGo').inspect}\n/usr/bin/make\n"
phase.always_out_of_date = '1'
packet.build_phases.delete(phase)
packet.build_phases.unshift(phase)
project.save
puts 'Extension target embedded. Provision the Runner and extension entitlements, matching Keychain group and DEVELOPMENT_TEAM. No signing identity was supplied or selected.'
