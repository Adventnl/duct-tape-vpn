# Safe Ubuntu deployment

The 2026-11-12 Windows session reached the owner's Ubuntu server through the paired Link Tunnel agent and deployed the trusted-console personal profile described in [personal setup](PERSONAL-SETUP.md). Its interface and NAT unit are active. A real Windows app test passed Connect, server reachability, tunnel routing, IPv4 HTTPS and Disconnect. DNS passed in the privileged setup check. These checks used LAN transport. The enrollment-based deployment below is a separate path and has not been activated. Keep credentials and private host inventory outside source control.

## Inspect and plan

From an already trusted Ubuntu console/SSH session:

```sh
umask 077
python3 deploy/dtvpn.py inspect > inspection.json
# Review all errors and complete missing checks. Do not publish this private host inventory.
cp deploy/config.example.json personal-config.json
# Set the verified exit interface and an unused UDP port.
python3 deploy/dtvpn.py plan --inspection inspection.json --config personal-config.json > plan.json
sha256sum plan.json
```

The inspector reads interfaces, IPv4/IPv6 routes, policy routing, listeners, nftables/iptables/UFW, existing WireGuard interface names, resolver/forwarding state, storage/memory and package versions. It does not read private keys or credentials. Inspect additional container/firewall managers, NetworkManager/netplan configuration and application dependencies manually when relevant. Failed/permission-denied checks are unknown, not empty state.

Verify there is no conflict with `dtvpn0`, nft table `inet dtvpn`, `10.77.0.0/24`, `fd77:6474:7670::/64`, chosen UDP port, 10.77.0.1:53/9443, or proposed public TLS ingress. Fixed-pool renumbering is not implemented. A conflicting pool is a deployment blocker. Inspect active UFW, Docker or other base-chain policies: the new table's accepts cannot override another chain's drop. Never flush/reset the host firewall.

Identify the router's WAN address and compare it with the independently observed public address. RFC1918 or 100.64/10 WAN addressing may indicate upstream NAT/CGNAT. Ask the ISP for a reachable address or configure user-approved IPv6 ingress only after IPv6 transport support is validated. There is no relay fallback. Double NAT needs forwarding at both routers. Use user-owned dynamic DNS if the WAN address changes; a static address is not assumed. Do not infer external reachability from a LAN handshake. Keep personal endpoints and certificates outside source/releases.

`stage` requires the SHA-256 of the exact reviewed plan. It saves backups and stages owned files only:

```sh
python3 deploy/dtvpn.py stage --plan plan.json --inspection inspection.json \
  --approval-sha256 EXACT_REVIEWED_PLAN_SHA256 --backup /YOUR/PRIVATE/BACKUP/DIRECTORY
```

Repeat inspection immediately before activation and compare it with the approved plan. Staging validates the supplied inspection/plan pair; it does not certify that the server has remained unchanged. Unmanaged/modified files and symlink destinations are rejected. Repeat staging preserves tracked installed bytes and makes another rollback point. Staging never activates units, opens ports, changes forwarding, installs packages or touches router policy.

## Activation prerequisites (require explicit approval)

The exact host-specific commands cannot be finalized until the host inspection is available. The following is the review checklist, not an instruction to apply blind changes:

- Install supported distro `wireguard-tools`, `nftables`, `unbound`, `dns-root-data`, `ca-certificates`, `python3` and a suitable existing TLS ingress after reviewing package versions/dependencies. Preserve package verification and existing services.
- Create dedicated `dtvpn-registry`, `dtvpn-gateway`, `dtvpn-dns` users and `dtvpn-enroll`, `dtvpn-admin`, `dtvpn-helper` groups. Only the registry and separately constrained private TLS ingress join dtvpn-admin. Gateway joins only dtvpn-enroll. Registry joins dtvpn-helper.
- Install verified server binaries under `/usr/local/lib/duct-tape-vpn`. Create `/var/lib/dtvpn` owned by dtvpn-registry mode 0700; `/var/lib/dtvpn-network` root-only mode 0700; `/var/lib/dtvpn-dns` owned by dtvpn-dns mode 0700. Seed the validating resolver's root trust anchor from the authenticated distro DNS root-data package into its writable state directory. Never bootstrap DNSSEC with verification disabled.
- Generate the server WireGuard private key locally with `wg genkey`, saved as `/var/lib/dtvpn-network/wireguard.key` mode 0600. Convert only its public key to application base64url for trusted bootstrap. Do not copy the server private key into the registry or gateway.
- On the MacBook, use “Set up Owner MacBook” to generate/export public keys from the native protected store. Transfer only that public JSON through the trusted console/SSH path. The native SE/provisioning path is not yet built/certified.
- Run `ductctl bootstrap --database /var/lib/dtvpn/registry.db --identity /var/lib/dtvpn/server.key --owner-public OWNER_PUBLIC.json --server-wireguard SERVER_PUBLIC_BASE64URL --endpoint VERIFIED_HOST:PORT` as the registry identity. It refuses a second bootstrap.
- Produce `ductctl owner-bundle --database ... --identity ... --origin https://PUBLIC_HOST --admin-origin https://PRIVATE_ADMIN_HOST:9443` and import it on the same Owner MacBook through the trusted connection. It binds the Owner signing/WireGuard public keys and server identity. Never import an unsolicited self-signed bundle from an invitation.
- Review enabling IPv4 forwarding against all host uses and preserve the exact old value. No script silently enables it. The network service refuses to start without it. It creates only its named interface and table; it tags both and verifies ownership before removal.
- Merge the public enrollment ingress template into the inspected TLS arrangement. Keep the private admin ingress bound only to 10.77.0.1:9443, in a separately constrained identity with only admin-socket access. Use valid TLS hostname certificates and an explicit renewal plan. The generic templates do not provision a domain/certificate or replace an existing nginx installation.
- Integrate only narrow UDP input, private DNS/admin and established forwarding permits in existing firewall policy. Apply the app-owned NAT/filter table after review. Public ingress allows only challenge/claim/poll and rate-limits per source. Never put public and private sockets behind the same unconstrained worker.
- Enable/start only the five dtvpn units after `systemd-analyze verify`, `unbound-checkconf`, `nft -c` and local health checks pass. The constrained units are supplied but have not been executed under systemd on Ubuntu here.
- Forward only the chosen WireGuard UDP/enrollment HTTPS ports in the router after external reachability/CGNAT review. Keep SSH and every unrelated rule unchanged. Run the complete remote acceptance matrix before calling the installation usable.

## Rollback and removal

For staged files only:

```sh
python3 deploy/dtvpn.py rollback --backup /YOUR/SAVED/BACKUP
```

Rollback refuses to overwrite a file changed since staging. For an active deployment, first review `deploy/remove.sh` (without arguments it prints its removal plan); removal interrupts tunnels and requires explicit approval. It stops/disables only the five owned units, verifies the interface alias/table marker before removing network resources and preserves keys, databases, backups, packages and shared forwarding settings. Restore the staged-file backup, then separately remove only the router/TLS rules recorded at activation. Check all other services before restoring a previously changed forwarding value. Clean removal never means deleting shared packages, resetting nftables, altering SSH or erasing personal state without an explicit separate decision.
