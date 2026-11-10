#!/bin/sh
set -eu
if [ "${1:-}" != '--apply-reviewed-removal' ]; then
 cat <<'PLAN'
Removal plan (not applied):
1. Intentional OFF on all clients; verify ordinary networking restored.
2. Stop only dtvpn-gateway, dtvpn-registry, dtvpn-helper, dtvpn-dns, dtvpn-network.
3. dtvpn-network stop verifies the owned interface alias and nft table comment before removing them.
4. Disable only those units. Restore staged unit/config files using dtvpn.py rollback and the saved backup.
5. Preserve /var/lib/dtvpn and /var/lib/dtvpn-network, encrypted backups and package installations.
6. Review and remove only the dedicated router/TLS ingress rules you approved at deployment.
7. Forwarding is a shared host setting: restore its prior value only after checking every other service.
Run with --apply-reviewed-removal only on the inspected server after approval. This step disconnects active tunnels.
PLAN
 exit 0
fi
for unit in dtvpn-gateway dtvpn-registry dtvpn-helper dtvpn-dns dtvpn-network; do
 systemctl stop "$unit"
 systemctl disable "$unit"
done
echo 'Owned services stopped. Restore staged files with dtvpn.py rollback using your recorded backup. State and keys retained.'
