# Status inventory

The product remains a development build. On 2026-11-12, the mobile interface was rebuilt and the Windows app compiled with its native plugin. A trusted-console personal server profile was deployed through Link Tunnel. The real Windows app passed Connect, server reachability, tunnel route selection, IPv4 HTTPS and Disconnect with ordinary routing restored. No signed Duct-Tape client release was published, and the enrollment journey has not passed on every platform.

## Server reconciliation repair — 2026-11-14

Both Mac and phone failed to connect after enrollment deployment. Inspection via
the paired LinkTunnel remote CLI found every service active but the live
WireGuard interface had no private key and its listening port changed between
reads. The saved interface configuration retained the original identity and UDP
51820. The registry's two-second peer reconciliation used peer-only `syncconf`,
which resets omitted interface fields.

The helper now uses validated `wg set` peer updates and explicit peer removals,
preserving interface identity, port and routing mark. The fixed Linux release
helper was deployed with a root-only binary/config backup; the saved key and port
were restored without restarting the shared interface or changing registered
peers. All seven VPN services remained active, and eight reconciliation cycles
preserved the identity, UDP port and four registered peers.

All 26 core security tests and strict core/server Clippy checks passed on macOS
and Ubuntu. `scripts/test-helper-reconcile.py` passed against the real release
helper in an isolated Linux network namespace, covering repeated additions and
removals, rejected invalid requests, empty desired sets, preserved server
identity/port/mark, and retained endpoint/keepalive/preshared-key settings. From
the current outside-home Wi-Fi, the Mac's handshake, routes, server reachability,
DNS and HTTPS checks passed and HTTPS reported the home exit address. The owner
also confirmed the phone displayed Connected after reconnecting. The Mac was
left connected.

## Current native Mac work

On 2026-11-12, a standalone SwiftUI/AppKit personal client was compiled on the owner's Apple Silicon Mac using Command Line Tools and installed as `/Applications/Duct-Tape VPN.app`. This local ad-hoc build uses a separately installed root-owned WireGuard Go/tools/Bash runtime and a LaunchDaemon, rather than the original Flutter Network Extension. Non-system dynamic libraries are bundled privately; installed tools and libraries have root ownership, no group/world write permission, and no user-writable Homebrew library bindings. The app receives only fixed connect/disconnect helper permission, not general passwordless sudo.

The server received a separate Mac peer and narrow persistent IPv4 NAT/UFW rules through Link Tunnel. The existing Windows peer, UFW policy and server Tailscale service were retained. The real Mac app's Connect and Disconnect actions passed. With the Mac's Tailscale backend explicitly `Stopped`, a direct handshake to the server's public IPv6 address, server ICMP, owned tunnel route selection, uncached DNS and TLS-validated IPv4 HTTPS passed. Disconnect removed the owned interface and restored ordinary routing. App closure also retained a fresh successful connection check with Tailscale stopped.

Later on 2026-11-12, the router's active fibre WAN was checked against an independently observed public IPv4 address, and an enabled UDP 51820 mapping to the existing server was verified in the saved router configuration. From an IPv4-only mobile-data hotspot, the real Mac app displayed Connected using the public IPv4 endpoint. Authenticated handshake, tunnel route selection, server ICMP, explicit DNS and tunnel-bound HTTPS passed; the HTTPS exit address matched the home WAN. Ordinary hostname resolution initially timed out because Tailscale's DNS override took priority. Disabling acceptance of Tailscale DNS on this Mac resolved the conflict, and both tunnel-bound hostname HTTPS and ordinary hostname HTTPS passed while connected. The final test left the tunnel OFF.

Outside-home IPv4 access is verified on that mobile network. Outside-home IPv6, NAT loopback, server LAN-address stability, ISP address-change recovery and censorship resistance remain unverified. The app has no kill switch; IPv6 internet egress is unavailable with the current personal server. ON intent is persisted for automatic reconnect, but reboot, sleep/wake and daemon-crash acceptance tests have not run. See [native Mac setup](MAC-PERSONAL.md).

## Current Windows and server work

- Flutter 3.50.0 and Dart 3.14.0 run on the Windows development PC. Static analysis and 22 Flutter tests pass, and the Windows debug application builds. Tests cover unverified, expired and failed checks, immediate connection progress, bounded timeouts, and stale snapshots after Disconnect.
- One real Windows integration test passes through the native plugin and installed service. It taps Connect and Disconnect, checks server ICMP, verifies the route to an internet address uses DuctTape, loads IPv4 HTTPS, and verifies ordinary routing returns after OFF. The privileged setup test also verifies DNS resolution through an explicit resolver.
- Five real Flutter widget captures cover mobile, compact desktop, dark connected fixtures, large text and settings. Simulated states are explicit. These are not device VPN tests.
- Nine deployment tests pass, including local key continuity, profile validation and injection rejection.
- The personal server WireGuard interface and its separately managed NAT unit are active. Existing UFW and Tailscale remain active. Server-side WireGuard reports a successful peer handshake and transferred traffic.
- Windows can control the fixed official `WireGuardTunnel$DuctTape` service after administrative provisioning. The adapter checks the service executable, configuration path and identity. Its background checks verify VPN routes, home-server ICMP, uncached DNS and IPv4 HTTPS before the UI shows Connected. Failed or expired evidence cannot show Connected. Connection checks do not issue a Protected attestation.
- The Windows personal profile is configured for LAN transport, full client routes and IPv4 egress. DNS uses explicit public resolvers through the tunnel. External router IPv4 reachability is now verified by the native Mac hotspot test; the Windows profile still needs a public endpoint and its own outside-home test. IPv6 internet forwarding remains unavailable.
- The official WireGuard Windows MSI and installed binaries have valid WireGuard LLC Authenticode signatures. Administrator-approved provisioning and its handshake, route, DNS and IPv4 HTTPS checks passed. The tunnel starts manually through the app and was left OFF after validation.

The inventory below records earlier implementation evidence and remaining work. Its cloud access and SDK blockers describe that earlier environment; the Windows/Link Tunnel evidence above supersedes them for this setup.

## Implemented and locally verified

| Capability | Evidence |
|---|---|
| Rust workspace and Linux server tools | Debug/release builds; rustfmt and warning-free Clippy |
| Enrollment/authentication/registry | 19 security/persistence tests, including invitation races, replay, HPKE possession, substitution, separate Owner authority, expiry, fingerprints, revocation, recovery, migrations, backup, endpoint validation and release-version binding |
| Native crypto boundary | 2 Rust bridge tests; C API and Android JNI source |
| Real gateway/registry journey | 8 process smoke checks: public admin isolation, size limits, HPKE enrollment, pending registry, Owner approval with unavailable-helper provisioning state, revocation and encrypted backup/restore integrity |
| Safe deployment files | 5 tests: exact-plan validation, repeat staging/backup/rollback, preserving unmanaged files, symlink rejection and narrow policy rendering |
| Update verification | 9 HTTPS TUF fixture checks: valid staging, installed-version rollback, persistent metadata advance/rollback, corrupt artifacts, signatures, expiry, Owner approval and protocol compatibility |
| Windows components | Service/filter executable cross-compiled and linked with MinGW; Flutter native plugin compiled to an object using real Flutter engine headers. No Windows runtime or complete app link test |
| Design | Four labeled Chromium concept renders, visually reviewed; no horizontal overflow at tested sizes |
| Dart source | 8 files parsed with a Dart grammar. This is syntax validation, not Flutter analysis, widget-test execution or compilation |

Test commands are in README.md. Zero-test binary/doc harnesses are not counted as functional tests. The build artifacts are unsigned review artifacts. Six resolved Rust packages still need complete upstream notice review before public redistribution; that inventory is included in the archive. Generated fixture credentials live only in temporary directories and are not in source/releases.

## Native implementation boundaries

On 2026-11-12, the Android, iOS and macOS Flutter hosts were added to source. Android's minimum SDK and shared Gradle/Kotlin versions now match the native plugin. Apple setup configures Runner and packet-extension entitlements, shared Keychain access and bundle metadata. The manual native workflow now includes unsigned macOS and iOS application compilation instead of stopping at Apple source preparation. Flutter analysis and all 22 shared tests pass on Windows. No VPN connectivity tests were run for this platform work. Android SDK/NDK and Xcode compilation have not run here, so these changes do not establish native build or device success.

- **macOS:** Flutter UI, Keychain storage, separate Secure Enclave/user-presence Owner identity, bootstrap import, Owner operations and independent Network Extension/WireGuardKit source. Requires actual Xcode project generation/embedding, provisioning, compile, signing and MacBook/hardware testing.
- **iOS:** Shared UI, protected native keys, enrollment and PacketTunnelProvider source. Requires legitimate app/extension profiles, Xcode/iOS build and physical-device testing. Developer Mode is insufficient evidence of entitlement access.
- **Android:** Official GoBackend integration, Keystore-sealed state, permission lifecycle, foreground supervisor, ON preference/retries and boot receiver source. Requires Flutter/SDK/NDK compilation and device testing; user-enabled OS lockdown is necessary for crash blocking.
- **Windows:** Credential Manager enrollment, worker-thread/native UI delivery, SCM/official tunnel-service host and owned persistent WFP policy source. Components cross-compile; signed official DLLs, full Flutter/MSVC build, secure configuration import/installer flow and Windows enforcement tests remain.

## Confirmed external blockers and exact next actions

| Blocker | Observation | Required action |
|---|---|---|
| Home-server access | `hanoryx-server` does not resolve from this executor. No trusted SSH route/known-host binding supplied | Provide a reachable SSH hostname/address/port through the supported secure environment connection, retain host-key verification, then run the read-only inspection. Do not send private keys/passwords in chat |
| Flutter artifacts | Official SDK download from storage.googleapis.com returns CONNECT 403 | Review/save the saved allowlist addition in environment settings and publish the environment; refresh runtime status, retry Flutter, generate runners and resolve/commit pubspec.lock |
| Linux WireGuard/TUN lab | Ordinary isolated namespace routing worked; kernel interface creation returned `Unknown device type`; official userspace fallback could not create a TUN device | Run the supplied disposable lab on a host with kernel WireGuard, or explicitly permit a TUN-backed userspace test and keep its result distinct from kernel validation |
| Apple toolchains/hardware | Linux executor has no Xcode, provisioned profiles or MacBook/iOS hardware | Build on the authorized Mac, verify SE availability and provision legitimate Network Extension/Keychain entitlements, then execute the acceptance matrix |
| Windows/Android runtime | No such OS/devices or signed drivers/SDK configuration attached | Supply suitable test/build devices; use the documented build steps and retain the unverified status until actual traffic tests pass |
| Release identities | No production TUF trust anchors, signing identities, domains/certificates or approved releases | Complete independent offline-root and platform-signing ceremonies. Keep secrets out of CI/source; publish only built/verified artifacts |

The network-policy addition and reusable `start_skill` toolchain/test instructions are saved in the draft; the draft has not been applied or published by this task. No secret requirements or values were added.

## Engineering still required

External access alone will not finish the product. Native build failures must be fixed when the SDKs become available. Missing product work includes a real home-exit/DNS verification pipeline, full Windows enrollment-to-service configuration handoff, robust endpoint recovery and deliberate identity rotation, safe pool/subnet-overlap handling, enforceable trusted-resource profiles, native deep-link/camera import, installer receipts/update handoff, platform accessibility audits and production packaging. Trusted-network exceptions are disabled; native adapters never emit a Protected attestation. These are explicit gaps, not implemented features awaiting only a checkbox.

The safest next milestone is the Owner MacBook plus Ubuntu vertical slice after read-only host inspection and legitimate Apple provisioning. Prepare and approve the exact host-specific network changes only after that inspection; do not activate the generic templates blindly. Keep Windows, iOS and Android in the acceptance matrix and extend the verified journey across them.


## Android activation and icon build — 2026-11-14

The Mac now builds Android locally using Flutter 3.50.0, JDK 17, SDK 36 and NDK
28.2.13676358. A release-mode APK with development signing is generated at
`dist/Duct-Tape-VPN-android-development.apk`. APK signature verification passed;
Rust, WireGuard, Flutter and app libraries are packaged for arm64-v8a,
armeabi-v7a and x86_64. The same APK installed and launched on an Android 36 ARM64
emulator. Activation layouts were inspected at phone and tablet sizes, light/dark
appearance and larger text. A rejected activation showed a recoverable error,
retained input and did not report a saved connection or crash the native process.

Server-console `generate` issues expiring, single-use codes; entering server
address + code saves a client connection after reconciliation, with automatic
polling and no second Owner approval. The CLI remembers its HTTPS origin. Real
local registry/gateway smoke checks pass for code issuance/redemption, automatic
Client authorization, no public admin route, no reuse and remembered origin.
The Rust suite, clippy, Flutter analysis/tests and deployment Python tests pass.
The new Android connection verifier binds HTTPS to the owned VPN network and
checks recent WireGuard traffic; it still requires real server/device validation.

The installed standalone Mac app now includes the shared tape icon and its
`CFBundleIconFile`, and its ad-hoc signature verifies. Its app bundle was backed
up under `/Library/Application Support/Duct-Tape VPN` before the icon update.
Helper, profile and tunnel state were preserved.

This work has not deployed the new registry/gateway/TLS route to the home server.
The saved SSH name `hanoryx-server` did not resolve on this Mac. The existing
personal WireGuard-only server needs an inspected migration preserving current
Mac/Windows peers before registry reconciliation can own that tunnel. No
physical Android tunnel or outside-home Android traffic success is claimed.


## Android code-only setup — 2026-11-14

Version 0.1.1 (Android versionCode 2) builds with a personal HTTPS enrollment
origin supplied through `DUCT_ACTIVATION_ORIGIN`. Its pairing screen presents one
activation-code input and Activate device. Generic builds retain manual server
and Owner invitation setup. The origin remains public build configuration;
one-use codes and private keys are not embedded.

The three native ABI builds, Flutter analysis and all 30 Flutter tests passed,
including code normalization, keyboard submission, invalid/rejected-code recovery
and generic setup. APK signature verification passed and its signer matched the
previous APK. `adb install -r` successfully updated the emulator from 0.1.0 to
0.1.1. Real emulator screenshots checked phone light appearance and tablet-sized
dark appearance with 1.3 font scale; the accessibility tree confirmed one input.
Evidence: `artifacts/android/code-only-phone-light.png`,
`artifacts/android/code-only-tablet-dark-large.png` and local build/signature logs.
The APK is available at `dist/Duct-Tape-VPN-0.1.1.apk` with a SHA-256 sidecar.
Physical-phone activation and tunnel operation were not exercised in this task.
