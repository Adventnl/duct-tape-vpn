#!/usr/bin/env ruby
# Exercise project integration without Xcode, signing, app launch or networking.
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

repo = File.expand_path('../..', __dir__)
def verify(condition, message)
  raise message unless condition
end

Dir.mktmpdir('dtvpn-apple-') do |scratch|
  FileUtils.mkdir_p(File.join(scratch, 'scripts/apple'))
  FileUtils.mkdir_p(File.join(scratch, 'clients/app'))
  FileUtils.mkdir_p(File.join(scratch, 'clients/native'))
  FileUtils.cp(__dir__ + '/embed-extension.rb', scratch + '/scripts/apple/')
  FileUtils.cp_r(repo + '/clients/native/apple', scratch + '/clients/native/')
  %w[ios macos].each do |platform|
    FileUtils.cp_r(repo + "/clients/app/#{platform}", scratch + '/clients/app/')
    script = scratch + '/scripts/apple/embed-extension.rb'
    output, status = Open3.capture2e(RbConfig.ruby, script, platform, 'dev.ducttape.test')
    verify(status.success?, output)
    host = scratch + "/clients/app/#{platform}"
    path = host + '/Runner.xcodeproj'
    project = Xcodeproj::Project.open(path)
    runner = project.targets.find { |target| target.name == 'Runner' }
    packet = project.targets.find { |target| target.name == 'PacketTunnel' }
    verify(packet && runner.dependencies.any? { |dep| dep.target == packet }, 'Missing packet extension dependency')
    verify(runner.copy_files_build_phases.any? { |phase| phase.files.any? { |file| file.file_ref == packet.product_reference } }, 'Missing embedded extension')
    packet.source_build_phase.files.each do |file|
      verify(File.file?(file.file_ref.real_path), "Broken source reference: #{file.file_ref.path}")
      verify(!Pathname.new(file.file_ref.path).absolute?, 'Machine-specific source reference')
    end
    verify(packet.package_product_dependencies.any? { |product| product.product_name == 'WireGuardKit' }, 'Missing WireGuardKit linkage')
    runner_info = Xcodeproj::Plist.read_from_path(host + '/Runner/Info.plist')
    verify(runner_info['DuctKeychainGroup'] == '$(AppIdentifierPrefix)dev.ducttape.shared', 'Missing shared Keychain setting')
    [runner, packet].each do |target|
      target.build_configurations.each do |configuration|
        settings = configuration.build_settings
        expected = 'dev.ducttape.test' + (target == packet ? '.PacketTunnel' : '')
        verify(settings['PRODUCT_BUNDLE_IDENTIFIER'] == expected, 'Bundle identifiers disagree')
        rights = Xcodeproj::Plist.read_from_path(host + '/' + settings['CODE_SIGN_ENTITLEMENTS'])
        verify(rights['keychain-access-groups'] == [runner_info['DuctKeychainGroup']], 'Keychain groups disagree')
        verify(rights['com.apple.developer.networking.networkextension'] == ['packet-tunnel-provider'], 'VPN entitlement missing')
        if platform == 'ios'
          verify(rights.keys.none? { |key| key.start_with?('com.apple.security.') }, 'macOS-only rights on iOS')
        else
          verify(rights['com.apple.security.network.client'] == true, 'Missing macOS network access')
          if target == runner && configuration.name == 'Debug'
            verify(rights['com.apple.security.cs.allow-jit'] == true, 'Flutter debug JIT right lost')
          end
        end
      end
    end
    before = File.binread(path + '/project.pbxproj')
    _, duplicate = Open3.capture2e(RbConfig.ruby, script, platform, 'dev.ducttape.test')
    verify(!duplicate.success?, 'Duplicate extension was accepted')
    verify(File.binread(path + '/project.pbxproj') == before, 'Duplicate attempt changed project')
    puts "#{platform}: extension linkage, portable source paths, entitlements and duplicate guard passed"
  end
end
