#!/bin/sh
# Produce a sideloadable personal development APK. The checked-in Android host
# currently uses the local Android debug key for release-mode signing.
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo"
command -v flutter >/dev/null
command -v cargo-ndk >/dev/null
: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK}"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to your installed Android NDK}"
scripts/build-native.sh android
mkdir -p artifacts/ui
cd clients/app
flutter pub get
flutter analyze
flutter test --dart-define="DUCT_ACTIVATION_ORIGIN=${DUCT_ACTIVATION_ORIGIN:-}"
flutter build apk --release --dart-define="DUCT_ACTIVATION_ORIGIN=${DUCT_ACTIVATION_ORIGIN:-}"
cd "$repo"
mkdir -p dist
cp clients/app/build/app/outputs/flutter-apk/app-release.apk dist/Duct-Tape-VPN-android-development.apk
shasum -a 256 dist/Duct-Tape-VPN-android-development.apk > dist/Duct-Tape-VPN-android-development.apk.sha256
printf '%s\n' 'Built dist/Duct-Tape-VPN-android-development.apk (development signing, no publication).'
