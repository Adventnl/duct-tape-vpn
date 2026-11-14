# Client build and native integration

All four platforms remain in scope. The Windows development PC now uses Flutter 3.50.0 and Dart 3.14.0. Its native client builds, and the personal connection passes a real Windows integration test on the home LAN. See [personal setup](PERSONAL-SETUP.md). Android and Apple builds still require their own SDKs, legitimate provisioning where applicable, and device validation. Earlier cloud SDK download restrictions do not apply to this Windows build environment. Keep TLS and SDK verification enabled.

With Flutter 3.50.0 installed:

```sh
scripts/prepare-clients.sh
cd clients/app
flutter analyze
flutter test
```

Android, iOS, macOS and Windows hosts are checked into `clients/app`. The preparation script copies only missing hosts and preserves existing projects, UI source and manifests. The Android host requires API 26 or later and shares its Gradle/Kotlin plugin versions with the native plugin. Apple builds use CocoaPods for the shared Darwin plugin and Rust XCFramework. Native plugin source is in `clients/native`; the app depends on it by local path.

## Apple

For the separately implemented, local personal Mac client, see [native Mac setup](MAC-PERSONAL.md). It builds using Command Line Tools and uses a root-owned WireGuard userspace helper, without Apple Developer membership or Network Extension provisioning. It has no kill switch. The Flutter/Network Extension path below remains a separate build and still requires provisioning.

Use a Mac with current compatible Xcode, CocoaPods/xcodeproj, Go, Rust cross targets and legitimate Apple signing/provisioning. The upstream WireGuard package supports macOS 12/iOS 15 minimums and links a separately built Go library. Its MIT license and exact pinned source are recorded in the notices. The native crypto static library is built as a multi-platform XCFramework:

```sh
scripts/build-native.sh apple
scripts/apple/fetch-wireguard.sh
ruby scripts/apple/embed-extension.rb macos YOUR_PROVISIONED_BUNDLE_ID
ruby scripts/apple/embed-extension.rb ios YOUR_PROVISIONED_BUNDLE_ID
sh scripts/apple/build-client.sh macos
sh scripts/apple/build-client.sh ios
```

The Ruby integration backs up the Xcode project, embeds the packet-tunnel extension, adds pinned WireGuardKit and its Go make phase, and configures matching Runner and extension Keychain groups. It preserves Flutter's macOS debug entitlements and keeps macOS sandbox keys out of iOS entitlements. It refuses duplicate extension targets. Run it once for each host. Use a fresh checkout when repeating CI probes. The standalone XcodeGen specification is also supplied for extension inspection.

The manual `native build probes` workflow now compiles Android, macOS and iOS applications, including the Apple packet extension. It uses Flutter 3.50.0 and Go 1.20.14 for the pinned WireGuardKitGo runtime patch. Apple builds use `--unsigned` to compile without installing or starting the VPN. That output needs legitimate signing and provisioning before device installation. The workflow has not been run as part of this Windows source check.

`ruby scripts/apple/test-embedding.rb` checks project integration in temporary copies without Xcode. It verifies the embedded extension, source paths, WireGuardKit linkage, matching Keychain groups, platform-specific entitlements and refusal to add a duplicate extension. Both platforms pass on Windows. This checks project configuration, not Swift compilation.

Provision the Runner and extension for Network Extension packet tunnels and their shared Keychain access group. Set the extension identifier to the Runner identifier plus `.PacketTunnel`; set `DuctKeychainGroup` in both Info.plists to the exact profile-authorized shared group. Use separate appropriate iOS/macOS entitlements and the Runner's required network sandbox permissions. Supply DEVELOPMENT_TEAM/profiles privately. The sample entitlement file is a starting point, not evidence of entitlement availability. Build WireGuardKitGo with the installed Go toolchain and Xcode build variables as required by its Makefile; validate library search/output placement on the first build.

`NETunnelProviderManager` persists ON intent, enables connect-on-demand, sets includeAllNetworks/enforceRoutes and disables LAN exclusions. The packet extension loads a Keychain persistent reference, creates WireGuardKit configuration with both default routes, private home DNS, MTU 1280 and keepalive. The app has no UI-close disconnect. Apple exceptions are represented as limited protection. Do not promise absolute fail-closed behavior across every extension termination or OS release.

The Owner setup path exists only on macOS. It creates a separate Secure Enclave P-256 identity using user presence; unsupported hardware fails rather than silently downgrading. Export public keys to the trusted server console, then import the signed Owner bundle through that same channel. Signing admin actions uses a fresh LAContext. This has not been exercised on the user's MacBook, Touch ID or any provisioning profile.

## Android

Use JDK 17, Android SDK 36, a compatible NDK and Gradle supplied by the generated Flutter host. The plugin minimum is API 26. Official `com.wireguard.android:tunnel:1.0.20260102` was verified as the current Maven Central release; the upstream library targets SDK 36/minimum 24 and Apache-2.0 licensing.

```sh
# Install a compatible cargo-ndk from crates.io with --locked; configure ANDROID_NDK_HOME.
scripts/build-native.sh android
cd clients/app
flutter build apk --debug
```

JNI libraries are generated for arm64-v8a, armeabi-v7a and x86_64. Keys/session/configuration are encrypted with a nonexported Android Keystore AES-GCM key, with record names as associated data and a fresh IV per write. The official GoBackend owns VpnService/socket protection. A separate foreground supervisor and persisted intent manage retries (bounded at 64 seconds), permission handling, restart and wake/boot recovery where Android allows it. OFF queues immediate reevaluation and tears down intentionally; UI destruction does not issue DOWN. Pairing uses a worker and securely checkpoints the candidate session before claim.

Users must enable Always-on and “Block connections without VPN” in Android's OS settings for process-crash blocking. A normal app cannot silently enable lockdown. The source does not query an unsupported hidden setting or claim it is enabled. Notification permission, OEM battery restrictions, boot/unlock behavior and all tunnel/lockdown transitions require physical-device tests. Server address + server-issued activation code and invitation paste/import are implemented; see [Android activation](ANDROID-ACTIVATION.md). Deep-link intent dispatch and camera QR capture are not yet integrated. Android connection checks bind HTTPS to the assigned VPN network and require recent WireGuard handshakes and increasing received traffic. Physical-device routing, DNS and crash behavior remain unvalidated.

## Windows

The personal setup path uses the official signed WireGuard Windows service, with fixed executable and configuration paths checked by `plugin/managed_tunnel.cpp`. The user receives only query/start/stop service rights. The compiled Flutter client controls that service through its native plugin. A real integration test verifies the app's Connect and Disconnect actions and routed IPv4 traffic. It does not certify failure blocking, reboot behavior or external router reachability.

### Experimental owned service

The older custom service/filter implementation below remains a separate, unvalidated path. It was not installed by personal setup.

The C++ service uses SCM, fixed service/config paths, a single-user/SYSTEM/Admin pipe DACL, remote-pipe rejection and a bounded command vocabulary. The separately installed official tunnel service is named `WireGuardTunnel$dtvpn` with unrestricted service SID, Nsi/TcpIp dependencies and the official WireGuardTunnelService entry point. DLL loading uses a protected installed directory plus system dependencies, never CWD/PATH. WireGuardNT and tunnel.dll are not bundled here.

Application-owned persistent WFP provider/sublayer/filter resources block ordinary outgoing IPv4/IPv6, with narrow loopback, tunnel-interface and fixed WireGuard transport process/address/port permits. The agent preserves desired ON and filters across service/UI termination, retries with bounded delay and serializes OFF against reconnection. This is unvalidated enforcement code, not a certified Windows kill switch. Endpoint transport currently requires a pre-resolved IPv4 binding installed deliberately. Boot-time filtering, live sockets, interface-LUID changes and suspend/resume must be tested.

The native plugin uses Credential Manager for device material and background enrollment with main-thread Flutter result delivery. Its C++ source compiled to an object against real Flutter engine headers. The agent/filter sources cross-compiled and linked into an **unsigned** PE executable with MinGW. Neither was executed on Windows, and this does not establish an MSVC/Flutter release build. The Windows enrollment-to-privileged-service config import path still requires a reviewed generated config and installer operation; it is not yet a one-click flow.

On a Windows build machine:

```text
scripts/build-native.sh windows
scripts/prepare-clients.sh
cd clients/app
flutter build windows
```

Use native equivalents of the shell scripts when MSYS is unavailable. `scripts/windows/install.ps1` requires elevation, exact reviewed artifact hashes, valid Authenticode signatures, a single authorized user SID, endpoint IPv4/port and generated strict configuration. It refuses existing installations. It does not authorize itself and has not been executed here. The service-only cross-built executable is for code review/testing, not a legitimate distribution path by itself. `uninstall.ps1` requires a successful intentional OFF before deleting only owned services; personal credentials/state are retained for deliberate cleanup.

## Shared outstanding integration

The requested acceptance journey is not complete on any platform. Home-exit/DNS verification is not implemented in native services; they never emit a Protected attestation. Automatic endpoint recovery/pin rotation, configurable pools and overlap checks, trusted-resource policy enforcement, signed updater GUI/install handoff, native accessibility audits and platform release packaging need further implementation and device validation. Source compilation cannot substitute for those checks.
