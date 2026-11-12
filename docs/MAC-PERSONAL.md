# Native personal Mac build

The standalone client in `clients/native/macos-personal` uses SwiftUI/AppKit and
the official WireGuard Go runtime through `wg-quick`. It builds with Apple's
Command Line Tools. It does not need Flutter, full Xcode, an Apple Developer
membership, or a Network Extension provisioning profile. This is a distinct local
personal client; the original Flutter/Network Extension client remains separate.

Build on Apple Silicon macOS with Command Line Tools and Homebrew:

```sh
brew install wireguard-tools
python3 scripts/apple/build-personal.py
```

Output is under `.local/macos-personal/payload`. The builder copies WireGuard
tools and Bash with their non-system libraries, relocates their library bindings,
and ad-hoc signs the local binaries. The root helper's installed runtime is owned
by root, and never loads executable code from user-writable Homebrew paths. This
output is neither a notarized release nor suitable for public redistribution
without the normal signing, packaging and license review.

## Provisioning and installation

Generate an independent X25519 key on the Mac and retain private material outside
the repository in a directory with mode 0700. Transfer only its public key over
the trusted server console. `deploy/add-personal-mac.py --public-key PUBLIC_KEY`
adds `10.77.0.3/32` and `fd77:6474:7670::3/128` to the previously inspected personal
server layout. It backs up the original owned files, retains the Windows peer,
adds narrow UFW and NAT rules, and updates the live interface without a restart.
It deliberately refuses a different server layout or a conflicting address.

Privately prepare `profile.json`, mode 0600, containing `privateKey`, `serverKey`
(standard base64 WireGuard keys), and an `endpoints` array of literal IP:port
addresses. IPv6 literals require brackets. No live keys or endpoints belong in
source control. Public IPv4 and IPv6 endpoints can be tried in order; no Tailscale
hostname, login, relay or coordination service is used by the client.

Run the reviewed installer with macOS administrator authorization:

```sh
sudo sh scripts/apple/install-personal.sh \
  "$PWD/.local/macos-personal/payload" /private/path/profile.json LOCAL_USERNAME
```

The installer refuses an existing installation rather than overwriting it. It
installs `/Applications/Duct-Tape VPN.app`, a root-owned runtime under
`/Library/PrivilegedHelperTools/dev.ducttape.personal`, a system LaunchDaemon, and
private state under `/var/db/duct-tape-vpn`. A validated sudoers entry authorizes
only that local user to invoke the fixed helper with `connect` or `disconnect`.
It does not grant a shell, arbitrary arguments or general sudo access. The
installation starts OFF. The native window then controls persisted ON/OFF intent.

## Connection evidence and limits

Connected requires an authenticated recent handshake, IPv4 route selection on
the owned tunnel, a reply from the server's tunnel address, an uncached DNS reply
through an explicit resolver, and certificate-validated HTTPS bound to the tunnel.
Checks repeat after ten seconds; the UI expires status after thirty seconds.
These are connection checks, not a certified protection or exit-identity claim.

The root daemon remembers ON intent across app closure and restart and retries
direct endpoints after failed checks. Failed checks remove the tunnel before a
new attempt. This implementation has **no kill switch**: ordinary traffic can
use the normal network while a tunnel is down or being retried. The personal
server forwards IPv4 only; IPv6 default traffic is carried into the tunnel and
has no internet egress. Changing this requires separately reviewed IPv6 server
routing and firewall work.

A public address alone does not establish travel reachability. IPv4 requires a
reachable public WAN address and UDP forwarding to the server; IPv6 requires
an IPv6-capable client network and inbound router permission. Tests on the home
LAN, including use of a public IPv6 address, cannot prove outside-home access.
The current IP literals do not automatically track ISP address/prefix changes.
WireGuard has no traffic obfuscation; China reachability is not guaranteed.

## Inspection and recovery

On 2026-11-12 the native build, installation, actual app Connect/Disconnect,
ordinary-route restoration, and continued traffic after app closure were tested
on the owner's MacBook. The successful connection used the server's public IPv6
address with Tailscale's backend explicitly stopped.

Later that day, the Huawei DN8245X6-10 router's active fibre WAN address matched
the independently observed public IPv4 address. An enabled user-defined mapping,
`DuctTape-WireGuard`, forwards only UDP 51820 to the existing server's LAN address
and port 51820. Its saved WAN, host, protocol and port values were reopened and
verified in the router UI. Live endpoint and host inventory remain outside source.

The Mac then connected through a phone's mobile-data hotspot with a different
public IPv4 address and no IPv6 underlay. The real app displayed Connected using
the public IPv4 endpoint. Helper checks passed authenticated handshake, tunnel
routes, server ICMP, uncached explicit DNS and TLS-validated IPv4 HTTPS. Additional
checks confirmed an internet route through the owned tunnel, replies from the
server, and HTTPS bound to that tunnel reporting the home WAN exit address.

Tailscale was running during this test and its supplemental DNS resolver took
priority over the VPN's configured resolvers. Explicit DNS queries succeeded but
ordinary hostname resolution timed out. Setting `tailscale set --accept-dns=false`
on this Mac resolved the conflict: both tunnel-bound HTTPS to a hostname and
ordinary HTTPS to `example.com` then passed while the VPN remained connected.
This setting disables Tailscale-provided DNS names on this Mac; IP-based Tailscale
configuration is retained. Restore with `tailscale set --accept-dns=true` if needed,
and retest coexistence before relying on both VPNs together.

The final test disconnected the owned tunnel and confirmed OFF. This validates
outside-home IPv4 access on the tested mobile network, not every network or
censorship resistance. NAT loopback, outside-home IPv6, address-change recovery
and server LAN-address stability across DHCP changes remain unverified.

The public status file is `/var/db/duct-tape-vpn/status.json`; it contains no
private keys. Detailed helper output is restricted to root in that directory.
To request OFF using the installed narrow permission:

```sh
sudo -n /Library/PrivilegedHelperTools/dev.ducttape.personal/duct-helper disconnect
```

Wait for OFF and confirm ordinary routing before unloading or replacing the
LaunchDaemon. Do not remove an active tunnel's configuration or kill only the UI
to disconnect it. Keep private identity state and server backups until deliberate
removal is requested. Reboot, sleep/wake and helper-crash behavior still need
hardware acceptance testing beyond a successful interactive connection.
