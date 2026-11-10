#!/bin/sh
# Generate the standard Flutter host projects without overwriting product source or existing projects.
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
command -v flutter >/dev/null
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
flutter create --no-pub --platforms=android,ios,macos,windows --org dev.ducttape --project-name duct_tape_vpn "$scratch/host"
for platform in android ios macos windows; do
  if [ -e "$repo/clients/app/$platform" ]; then
    echo "$platform host exists; preserving it"
  else
    cp -R "$scratch/host/$platform" "$repo/clients/app/$platform"
  fi
done
cd "$repo/clients/app"
flutter pub get
# Commit generated hosts and pubspec.lock after platform review. Never add signing credentials.
