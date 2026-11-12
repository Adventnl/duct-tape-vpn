#!/bin/sh
# Install only the reviewed local build. macOS administrator authorization required.
set -eu
umask 077
test "$(id -u)" = 0
test "$#" = 3
payload=$1
profile=$2
owner=$3
case "$owner" in ''|*[!a-zA-Z0-9_-]*) echo 'Invalid local user' >&2; exit 1;; esac
test "$(id -u "$owner")" -ge 501
runtime=/Library/PrivilegedHelperTools/dev.ducttape.personal
state=/var/db/duct-tape-vpn
job=/Library/LaunchDaemons/dev.ducttape.personal.plist
policy=/etc/sudoers.d/duct-tape-vpn
test -f "$payload/runtime/duct-helper"
test -f "$profile"
for existing in "$runtime" "$state" "$job" "$policy" '/Applications/Duct-Tape VPN.app'; do
    if test -e "$existing" || test -L "$existing"; then
        echo "Existing installation requires review: $existing" >&2
        exit 1
    fi
done
/usr/bin/codesign --verify --deep --strict "$payload/Duct-Tape VPN.app"
/usr/bin/install -d -o root -g wheel -m 755 "$runtime" "$state"
/usr/bin/ditto "$payload/runtime" "$runtime"
/usr/sbin/chown -R root:wheel "$runtime"
/bin/chmod -R go-w "$runtime"
/usr/bin/install -o root -g wheel -m 600 "$profile" "$state/profile.json"
/usr/bin/printf 'off\n' > "$state/desired"
/bin/chmod 600 "$state/desired"
/usr/bin/install -d -o root -g wheel -m 755 /etc/sudoers.d
temporary_policy="$state/sudoers-review"
/usr/bin/printf '%s ALL=(root) NOPASSWD: %s/duct-helper connect, %s/duct-helper disconnect\n' "$owner" "$runtime" "$runtime" > "$temporary_policy"
/usr/sbin/visudo -cf "$temporary_policy"
/usr/bin/install -o root -g wheel -m 440 "$temporary_policy" "$policy"
/bin/rm "$temporary_policy"
/usr/sbin/visudo -c
/bin/cat > "$job" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>dev.ducttape.personal</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/dev.ducttape.personal/duct-helper</string><string>daemon</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>StandardOutPath</key><string>/var/db/duct-tape-vpn/daemon.log</string>
<key>StandardErrorPath</key><string>/var/db/duct-tape-vpn/daemon.log</string>
</dict></plist>
PLIST
/usr/sbin/chown root:wheel "$job"
/bin/chmod 644 "$job"
/usr/bin/plutil -lint "$job"
/usr/bin/ditto "$payload/Duct-Tape VPN.app" '/Applications/Duct-Tape VPN.app'
/usr/sbin/chown -R root:wheel '/Applications/Duct-Tape VPN.app'
/bin/chmod -R go-w '/Applications/Duct-Tape VPN.app'
/bin/launchctl bootstrap system "$job"
echo 'Duct-Tape VPN installed. The tunnel is OFF until Connect is selected.'
