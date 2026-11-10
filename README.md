# Duct-Tape VPN

A personal WireGuard VPN with your Ubuntu server as its only exit. No account, relay or coordination service.

**Development build, not ready for everyday protection.** The Rust enrollment, registry, gateway, recovery and update verification work locally. Flutter and native integrations are source implementations awaiting platform compilation and device validation. No home-server deployment has been performed. Read [the status inventory](docs/STATUS.md) before installing anything.

The main screen is intentionally quiet: branding, one switch, one truthful status. [View the labeled desktop concept](docs/design/desktop.png), [mobile](docs/design/mobile.png), [dark](docs/design/dark.png) and [large text](docs/design/large-text.png). These are browser-rendered design studies, not screenshots of a working native VPN.

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

## Server workflow

Start with [safe deployment](docs/DEPLOYMENT.md). `deploy/dtvpn.py inspect` is read-only. Its plan and staging commands do not activate services, install packages, change forwarding, or alter host/router firewall rules. Never deploy a generic plan to a multipurpose host without reviewing its actual inspection.

[Architecture](docs/ARCHITECTURE.md) · [protocol and threat model](docs/SECURITY.md) · [recovery](docs/RECOVERY.md) · [updates](docs/UPDATES.md) · [design](docs/DESIGN.md) · [acceptance matrix](docs/ACCEPTANCE.md) · [license notices](THIRD_PARTY_NOTICES.md)
