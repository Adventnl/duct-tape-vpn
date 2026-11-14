# Duct-Tape VPN

A personal WireGuard VPN with your Ubuntu server as its only exit. No account, relay or coordination service.

**Development build, not certified for everyday protection.** The Flutter interface has been rebuilt with neutral surfaces, blue controls and restrained glass. The Windows app and personal server profile pass a real Connect, routed IPv4 HTTPS and Disconnect test on the home LAN. A standalone native Mac client is also installed. After router UDP forwarding was configured, the Mac passed direct public IPv4 WireGuard, routed HTTPS, DNS and home-exit address checks from a mobile-data hotspot. Tailscale's DNS override was disabled on this Mac to resolve a conflict with ordinary hostname lookups. Public IPv6 was previously tested from home. Read [Windows personal setup](docs/PERSONAL-SETUP.md), [native Mac setup](docs/MAC-PERSONAL.md) and [the status inventory](docs/STATUS.md) for evidence and limits.

The main screen has one connection action, verified connection status, a server group and hierarchical settings. It shows Not connected, Connecting or Connected. Connected requires recent successful traffic checks through the VPN. Flutter render tests cover light and dark appearance, phone and compact desktop widths, and double text size. The earlier browser studies in `docs/design/` are archived concepts. They do not represent the current interface.

## Build and test

Rust 1.91.1, a C compiler and standard build tools are required. Toolchain selection is pinned in `rust-toolchain.toml`; dependency versions are in `Cargo.lock`.

```sh
# In the prepared cloud workspace, activate its user-owned toolchains:
. scripts/environment.sh
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo build --workspace --release --locked
python3 -m unittest discover -s deploy/tests -v
python3 scripts/smoke.py
# Also requires Python cryptography (see scripts/test-requirements.txt).
python3 scripts/test-updates.py
scripts/package-linux.sh
```

The smoke test starts real local registry and gateway processes with temporary identities. It deliberately leaves the privileged helper unavailable and checks that the registry reports provisioning rather than pretending a peer is ready. It also tests an age-encrypted backup/restore round trip. The update test builds an ephemeral HTTPS TUF repository; its test keys are never product trust anchors.

For the disposable traffic lab:

```sh
docker build -f tests/network/Dockerfile -t dtvpn-network-lab .
docker run --rm --cap-add NET_ADMIN --cap-add SYS_ADMIN \
  --sysctl net.ipv4.ip_forward=1 --security-opt apparmor=unconfined \
  dtvpn-network-lab
```

This changes only the test container's networking. A host kernel supporting WireGuard is required. An explicitly labeled official wireguard-go fallback needs a permitted `/dev/net/tun`; it does not validate Linux kernel integration. The cloud executor used here has neither capability, so VPN traffic tests have not passed here.

For clients, see [platform build instructions](docs/PLATFORMS.md). Standard Flutter runners are generated using `scripts/prepare-clients.sh`; existing hosts and product sources are preserved. Native crypto builds use `scripts/build-native.sh`. Flutter SDK downloads need `storage.googleapis.com`; the required environment-policy addition was saved as a draft, not applied.

## Android activation

The Android client supports server address + one-use activation code, saved for
future connections. The first trusted-console command is
`sudo dvpn generate --origin https://YOUR-SERVER`; later runs are `sudo dvpn generate`.
The server must run the updated registry, gateway and TLS ingress. The existing
personal WireGuard-only deployment requires a separate migration first.
See [Android installation and activation](docs/ANDROID-ACTIVATION.md).

## Server workflow

Start with [safe deployment](docs/DEPLOYMENT.md). `deploy/dtvpn.py inspect` is read-only. Its plan and staging commands do not activate services, install packages, change forwarding, or alter host/router firewall rules. Never deploy a generic plan to a multipurpose host without reviewing its actual inspection.

[Architecture](docs/ARCHITECTURE.md) · [protocol and threat model](docs/SECURITY.md) · [recovery](docs/RECOVERY.md) · [updates](docs/UPDATES.md) · [design](docs/DESIGN.md) · [acceptance matrix](docs/ACCEPTANCE.md) · [license notices](THIRD_PARTY_NOTICES.md)
