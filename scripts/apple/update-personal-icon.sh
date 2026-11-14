#!/bin/sh
# Replace only the reviewed application bundle; leave VPN/helper state alone.
set -eu
app='/Applications/Duct-Tape VPN.app'
candidate=$1
test "$(id -u)" = 0
test "$#" = 1
test ! -L "$app"
test -f "$candidate/Contents/Resources/DuctTape.icns"
/usr/bin/codesign --verify --deep --strict "$candidate"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist")" = dev.ducttape.personal
backup="/Library/Application Support/Duct-Tape VPN/icon-backup-$(date +%Y%m%d%H%M%S).app"
/bin/mkdir -p '/Library/Application Support/Duct-Tape VPN'
/usr/bin/ditto "$app" "$backup"
/usr/bin/ditto "$candidate" "$app"
/usr/sbin/chown -R root:wheel "$app"
/bin/chmod -R go-w "$app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/touch "$app"
