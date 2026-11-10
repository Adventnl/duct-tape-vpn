#!/bin/sh
# Run only after inspection, backup and explicit review. Never alter another interface/table.
set -eu
case "${1:-}" in
 start)
   test "$(sysctl -n net.ipv4.ip_forward)" = 1 || { echo 'IPv4 forwarding requires separate host approval' >&2; exit 1; }
   if ip link show dtvpn0 >/dev/null 2>&1; then
     echo 'dtvpn0 already exists: inspect ownership before restarting' >&2; exit 1
   fi
   if nft list table inet dtvpn >/dev/null 2>&1; then
     echo "dtvpn table exists: inspect ownership before start" >&2; exit 1
   fi
   test -r /var/lib/dtvpn-network/wireguard.key
   nft -c -f /etc/duct-tape-vpn/firewall.nft
   ip link add dtvpn0 type wireguard
   ip link set dtvpn0 alias dtvpn-managed-v1
   trap 'ip link delete dtvpn0' EXIT HUP INT TERM
   wg set dtvpn0 private-key /var/lib/dtvpn-network/wireguard.key listen-port @WIREGUARD_PORT@
   ip address add 10.77.0.1/24 dev dtvpn0
   ip -6 address add fd77:6474:7670::1/64 dev dtvpn0
   ip link set dev dtvpn0 mtu 1280 up
   nft -f /etc/duct-tape-vpn/firewall.nft
   trap - EXIT HUP INT TERM
   ;;
 stop)
   # Only use after verifying these resources still belong to this installation.
   ip -j link show dtvpn0 | python3 -c 'import json,sys; assert json.load(sys.stdin)[0].get("ifalias")=="dtvpn-managed-v1"'
   nft -j list table inet dtvpn | python3 -c 'import json,sys; assert any(x.get("table",{}).get("comment")=="Duct-Tape VPN managed v1" for x in json.load(sys.stdin)["nftables"])'
   nft delete table inet dtvpn
   ip link delete dtvpn0
   ;;
 *) exit 2 ;;
esac
