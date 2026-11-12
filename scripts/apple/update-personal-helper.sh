#!/bin/sh
# Replace the compiled helper only after requesting OFF and verifying cleanup.
set -eu
test "$(id -u)" = 0
test "$#" = 1
source_helper=$1
runtime=/Library/PrivilegedHelperTools/dev.ducttape.personal
state=/var/db/duct-tape-vpn
test -f "$source_helper"
test -d "$runtime"
"$runtime/duct-helper" disconnect
count=0
while test "$count" -lt 30; do
    if /usr/bin/grep -q '"phase":"off"' "$state/status.json"; then break; fi
    /bin/sleep 1
    count=$((count + 1))
done
/usr/bin/grep -q '"phase":"off"' "$state/status.json"
test ! -e /var/run/wireguard/DuctTape.name
/bin/launchctl bootout system/dev.ducttape.personal
/usr/bin/install -o root -g wheel -m 755 "$source_helper" "$runtime/duct-helper"
/bin/launchctl bootstrap system /Library/LaunchDaemons/dev.ducttape.personal.plist
echo 'Updated native helper; tunnel is OFF.'
