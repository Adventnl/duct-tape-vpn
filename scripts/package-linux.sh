#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo"
cargo build --workspace --release --locked
python3 scripts/collect-rust-licenses.py
mkdir -p dist
version=$(sed -n 's/^version = "\([^"]*\)"/\1/p' Cargo.toml | head -1)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir -p "$scratch/duct-tape-vpn-$version/bin"
for name in ductctl duct-registry duct-gateway duct-helper duct-update; do
 install -m 0755 "target/release/$name" "$scratch/duct-tape-vpn-$version/bin/$name"
done
cp -R artifacts/rust-licenses "$scratch/duct-tape-vpn-$version/"
cp -R deploy docs licenses LICENSE THIRD_PARTY_NOTICES.md "$scratch/duct-tape-vpn-$version/"
tar --exclude=__pycache__ -C "$scratch" -czf "dist/duct-tape-vpn-$version-linux-x86_64-unsigned.tar.gz" "duct-tape-vpn-$version"
sha256sum "dist/duct-tape-vpn-$version-linux-x86_64-unsigned.tar.gz" > "dist/duct-tape-vpn-$version-linux-x86_64-unsigned.tar.gz.sha256"
echo 'Unsigned artifact built. No release was published.'
