#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo"
case "${1:-}" in
 android)
   command -v cargo-ndk >/dev/null || { echo 'Install cargo-ndk from crates.io with --locked; set ANDROID_NDK_HOME to the SDK NDK.' >&2; exit 1; }
   cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o clients/native/android/src/main/jniLibs build -p duct-bridge --release --locked
   ;;
 apple)
   test "$(uname -s)" = Darwin
   for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin; do
     rustup target add "$target"
     cargo build -p duct-bridge --target "$target" --release --locked
   done
   scratch=$(mktemp -d)
   trap 'rm -rf "$scratch"' EXIT HUP INT TERM
   lipo -create target/aarch64-apple-ios-sim/release/libduct_bridge.a target/x86_64-apple-ios/release/libduct_bridge.a -output "$scratch/simulator.a"
   lipo -create target/aarch64-apple-darwin/release/libduct_bridge.a target/x86_64-apple-darwin/release/libduct_bridge.a -output "$scratch/macos.a"
   mkdir -p clients/native/darwin/Libraries
   test ! -e clients/native/darwin/Libraries/DuctBridge.xcframework
   xcodebuild -create-xcframework -library target/aarch64-apple-ios/release/libduct_bridge.a -library "$scratch/simulator.a" -library "$scratch/macos.a" -output clients/native/darwin/Libraries/DuctBridge.xcframework
   ;;
 windows)
   cargo build -p duct-bridge --target x86_64-pc-windows-msvc --release --locked
   mkdir -p clients/native/windows/bin
   cp target/x86_64-pc-windows-msvc/release/duct_bridge.dll clients/native/windows/bin/
   ;;
 *) echo 'Usage: scripts/build-native.sh android|apple|windows' >&2; exit 2;;
esac
