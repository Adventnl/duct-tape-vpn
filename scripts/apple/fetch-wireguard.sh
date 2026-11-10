#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
path="$repo/.local/wireguard-apple"
pin=2fec12a6e1f6e3460b6ee483aa00ad29cddadab1
if [ ! -e "$path" ]; then
 mkdir -p "$repo/.local"
 git clone https://github.com/WireGuard/wireguard-apple.git "$path"
 git -C "$path" checkout --detach "$pin"
fi
test "$(git -C "$path" rev-parse HEAD)" = "$pin"
test -z "$(git -C "$path" status --porcelain)"
echo 'Pinned upstream source verified. Use its documented WireGuardKitGo make integration with your installed Go/Xcode toolchains.'
