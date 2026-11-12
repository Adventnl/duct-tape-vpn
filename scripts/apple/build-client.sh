#!/bin/sh
# Compile only. Never launch the app or start a VPN.
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
platform=${1:-}
mode=${2:-}
case "$platform:$mode" in
  ios:|macos:|ios:--unsigned|macos:--unsigned) ;;
  *) echo 'Usage: build-client.sh ios|macos [--unsigned]' >&2; exit 2 ;;
esac
test "$(uname -s)" = Darwin
cd "$repo/clients/app"
flutter pub get
if [ "$platform" = ios ]; then
  if [ "$mode" = --unsigned ]; then
    flutter build ios --debug --no-codesign
  else
    flutter build ios --debug
  fi
elif [ "$mode" = --unsigned ]; then
  # Flutter has no macOS --no-codesign switch.
  flutter build macos --debug --config-only
  pod install --project-directory=macos
  xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
    -configuration Debug -destination 'generic/platform=macOS' \
    -derivedDataPath build/macos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
else
  flutter build macos --debug
fi
