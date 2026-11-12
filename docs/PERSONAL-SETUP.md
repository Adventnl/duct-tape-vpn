# Personal Windows connection

This path provisions one personal Windows peer through the already trusted server console. It uses the official WireGuard Windows service. It does not bootstrap an Owner MacBook or activate the enrollment registry. Existing enrollment code remains available separately.

## Current evidence

The server was inspected through Link Tunnel. Ubuntu 26.04, its WireGuard kernel support, active UFW policy, available UDP port and nonoverlapping VPN subnet were checked. WireGuard tools were installed from the distro package repository. `wg-quick@dtvpn0`, the owned NAT unit and Tailscale report active. The server listens on UDP 51820 and reports a peer handshake and transferred traffic.

The Windows Flutter application and native plugin build with MSVC. The official WireGuard MSI and installed binaries have valid WireGuard LLC Authenticode signatures. Administrator-approved installation passed handshake, route, DNS and IPv4 HTTPS checks. A separate real Windows integration test tapped the app's Connect and Disconnect controls, reached the server, verified internet route selection and HTTPS, and confirmed ordinary routing was restored after OFF. A debug application is not a signed distribution release.

## Provisioning files

`deploy/personal-server.py prepare` validates the peer and inspected host, generates server keys locally, and saves private preparation state. `activate` creates the owned interface configuration, enables IPv4 forwarding in an owned sysctl file, adds narrow UFW rules and installs an owned NAT unit. It refuses existing resources rather than adopting them.

Ubuntu's AppArmor profile prevents wg-quick from executing arbitrary custom helpers. NAT therefore runs in `dtvpn-personal-nat.service`, ordered before the WireGuard service with an instance-specific drop-in. The profile remains enforced.

Server private keys and preparation state stay under `/etc/duct-tape-vpn/personal` and `/etc/wireguard`. Local client keys and the generated profile stay in the owner's restricted LocalAppData `DuctTapeVPN/setup` directory. No keys, live endpoints or private host inventory belong in the repository.

`scripts/windows/prepare-personal.py` generates and reuses the local X25519 identity. It consumes only trusted server public data and rejects endpoint text that could introduce profile fields. It requires Python cryptography in a separate environment.

`scripts/windows/install-personal.ps1` requires administrator execution, a signature-verified official MSI, a canonical generated profile and one authorized user SID. It stores the service profile under protected Program Files, grants the user only service query/start/stop rights, and tests handshake, route selection, DNS and IPv4 HTTPS. Failed tests stop the owned tunnel. Successful tests also stop it and set manual startup so the app controls the next connection.

## Verification limits

The configured Windows endpoint is on the home LAN. Router UDP forwarding and public IPv4 access were subsequently verified from a mobile-data hotspot using the separate native Mac client; see [native Mac setup](MAC-PERSONAL.md). The Windows profile still needs a public endpoint and its own outside-home test before remote Windows use is established.

The profile routes both IPv4 and IPv6 into the tunnel. This personal server profile forwards IPv4 only, so IPv6 internet access is intentionally unavailable through it. DNS uses Cloudflare's public resolvers through the tunnel; a private validating resolver is not part of this profile.

The native adapter reads official service state and runs background connection checks. Connected requires routes through DuctTape, a reply from the home server, uncached DNS resolution and TLS-validated IPv4 HTTPS. Checks repeat after ten seconds. Passing evidence expires after thirty seconds, each check has a fifteen-second deadline, and the UI bounds Connecting to twenty seconds. Service changes invalidate earlier results. Connection timestamps are separate from protection evidence. These checks do not attest exit identity, DNS privacy or failure blocking, and never emit Protected. Suspend, reboot, process failure, independent kill-switch validation, mobile hardware tests and production signing remain separate acceptance work.

Run `flutter test integration_test/windows_connection_test.dart -d windows` only on the provisioned Windows PC. It changes the real tunnel state, waits for the verified Connected headline, checks traffic, and verifies Not connected and ordinary routing after Disconnect. It leaves the tunnel OFF. It saves a render from the live connection at `artifacts/ui/windows-live-connected.png`. Rebuild the normal application afterward with `flutter build windows --debug`, because the integration runner uses the same build output directory.

## Review and removal

Review the saved `before.json` before changing the host again. Stop the owned WireGuard service before removal. The NAT helper checks its table ownership comment before deleting that table. Remove only UFW rules marked `dtvpn-personal` and owned files. Keep keys and backups until the owner explicitly requests deletion. Restoring the old global IPv4 forwarding value requires checking whether another service now needs forwarding.
