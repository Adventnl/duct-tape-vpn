# Status inventory

The product remains a development build. On 2026-11-12, the mobile interface was rebuilt and the Windows app compiled with its native plugin. A trusted-console personal server profile was deployed through Link Tunnel. The real Windows app passed Connect, server reachability, tunnel route selection, IPv4 HTTPS and Disconnect with ordinary routing restored. No signed Duct-Tape client release was published, and the enrollment journey has not passed on every platform.

## Current native Mac work

On 2026-11-12, a standalone SwiftUI/AppKit personal client was compiled on the owner's Apple Silicon Mac using Command Line Tools and installed as `/Applications/Duct-Tape VPN.app`. This local ad-hoc build uses a separately installed root-owned WireGuard Go/tools/Bash runtime and a LaunchDaemon, rather than the original Flutter Network Extension. Non-system dynamic libraries are bundled privately; installed tools and libraries have root ownership, no group/world write permission, and no user-writable Homebrew library bindings. The app receives only fixed connect/disconnect helper permission, not general passwordless sudo.

The server received a separate Mac peer and narrow persistent IPv4 NAT/UFW rules through Link Tunnel. The existing Windows peer, UFW policy and server Tailscale service were retained. The real Mac app's Connect and Disconnect actions passed. With the Mac's Tailscale backend explicitly `Stopped`, a direct handshake to the server's public IPv6 address, server ICMP, owned tunnel route selection, uncached DNS and TLS-validated IPv4 HTTPS passed. Disconnect removed the owned interface and restored ordinary routing. App closure also retained a fresh successful connection check with Tailscale stopped.

Public IPv4 attempts did not complete a handshake from home. This does not distinguish missing forwarding from unsupported NAT loopback. Router review and testing from an independent network were deferred by the owner. Using a public IPv6 address on the same home LAN does not validate the router's external inbound policy. The app is not established as travel-ready or censorship resistant. It has no kill switch; IPv6 internet egress is unavailable with the current personal server. ON intent is persisted for automatic reconnect, but reboot, sleep/wake and daemon-crash acceptance tests have not run. See [native Mac setup](MAC-PERSONAL.md).

## Current Windows and server work

- Flutter 3.50.0 and Dart 3.14.0 run on the Windows development PC. Static analysis and 22 Flutter tests pass, and the Windows debug application builds. Tests cover unverified, expired and failed checks, immediate connection progress, bounded timeouts, and stale snapshots after Disconnect.
- One real Windows integration test passes through the native plugin and installed service. It taps Connect and Disconnect, checks server ICMP, verifies the route to an internet address uses DuctTape, loads IPv4 HTTPS, and verifies ordinary routing returns after OFF. The privileged setup test also verifies DNS resolution through an explicit resolver.
- Five real Flutter widget captures cover mobile, compact desktop, dark connected fixtures, large text and settings. Simulated states are explicit. These are not device VPN tests.
- Nine deployment tests pass, including local key continuity, profile validation and injection rejection.
- The personal server WireGuard interface and its separately managed NAT unit are active. Existing UFW and Tailscale remain active. Server-side WireGuard reports a successful peer handshake and transferred traffic.
- Windows can control the fixed official `WireGuardTunnel$DuctTape` service after administrative provisioning. The adapter checks the service executable, configuration path and identity. Its background checks verify VPN routes, home-server ICMP, uncached DNS and IPv4 HTTPS before the UI shows Connected. Failed or expired evidence cannot show Connected. Connection checks do not issue a Protected attestation.
- The personal profile is configured for LAN transport, full client routes and IPv4 egress. DNS uses explicit public resolvers through the tunnel. IPv6 internet forwarding and external router reachability are not established.
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
