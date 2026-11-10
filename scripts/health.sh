#!/bin/sh
# Trusted Ubuntu console. Never print keys, environment values or DNS queries.
set -eu
for unit in dtvpn-network dtvpn-helper dtvpn-registry dtvpn-gateway dtvpn-dns; do
 systemctl is-active --quiet "$unit"
 echo "$unit active"
done
ip -j link show dtvpn0 | python3 -c 'import json,sys; x=json.load(sys.stdin)[0]; assert x.get("ifalias")=="dtvpn-managed-v1"; print("owned interface present")'
test "$(sysctl -n net.ipv4.ip_forward)" = 1
nft list table inet dtvpn >/dev/null
unbound-checkconf /etc/duct-tape-vpn/unbound.conf
runuser -u dtvpn-registry -- /usr/local/lib/duct-tape-vpn/ductctl check --database /var/lib/dtvpn/registry.db --identity /var/lib/dtvpn/server.key
dig @10.77.0.1 dnssec-failed.org A +time=3 +tries=1 | python3 -c 'import sys; assert "status: SERVFAIL" in sys.stdin.read(); print("bogus DNSSEC answer rejected")'
dig @10.77.0.1 cloudflare.com A +dnssec +time=3 +tries=1 | python3 -c 'import sys; x=sys.stdin.read(); assert "status: NOERROR" in x and " ad" in x; print("validated DNS response received")'
echo 'Local service checks passed. Run remote ACCEPTANCE.md; this does not prove exit routing or client protection.'
