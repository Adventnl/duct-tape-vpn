#!/usr/bin/env python3
"""Provision one explicitly authorized Windows peer on an inspected Ubuntu host.

This trusted-console path does not create enrollment/Owner identities. It keeps
existing UFW/Tailscale policy and gives only this peer IPv4 internet forwarding.
IPv6 is carried into the tunnel but deliberately not forwarded by this profile.
"""
import argparse
import base64
import ipaddress
import json
import os
from pathlib import Path
import subprocess

ROOT = Path('/etc/duct-tape-vpn/personal')
CONF = Path('/etc/wireguard/dtvpn0.conf')
NAT = Path('/usr/local/lib/duct-tape-vpn/personal-nat')
SYSCTL = Path('/etc/sysctl.d/90-dtvpn-personal.conf')
UNIT = Path('/etc/systemd/system/dtvpn-personal-nat.service')
DROPIN = Path('/etc/systemd/system/wg-quick@dtvpn0.service.d/10-dtvpn-personal.conf')
MARKER = 'Duct-Tape VPN personal v1'


def run(*args, input=None):
    return subprocess.run(args, input=input, text=True, capture_output=True, check=True).stdout.strip()


def validate_key(value):
    raw = base64.b64decode(value, validate=True)
    if len(raw) != 32 or raw == bytes(32):
        raise ValueError('Expected a nonzero 32-byte WireGuard public key')
    return value


def prepare(client_public, endpoint, interface, port):
    validate_key(client_public)
    ipaddress.ip_address(endpoint)
    if not interface or len(interface) > 15 or not all(c.isalnum() or c in '_.-' for c in interface):
        raise ValueError('Invalid exit interface')
    if not 1024 <= port <= 65535:
        raise ValueError('Invalid UDP port')
    for path in (ROOT, CONF, NAT, SYSCTL, UNIT, DROPIN):
        if path.exists() or path.is_symlink():
            raise ValueError(f'Existing resource requires review: {path}')
    interfaces = json.loads(run('ip', '-j', 'link', 'show'))
    if any(x['ifname'] == 'dtvpn0' for x in interfaces):
        raise ValueError('dtvpn0 already exists')
    if interface not in [x['ifname'] for x in interfaces]:
        raise ValueError('Exit interface does not exist')
    tables = json.loads(run('nft', '-j', 'list', 'tables'))['nftables']
    if any(x.get('table', {}).get('name') == 'dtvpn_personal' for x in tables):
        raise ValueError('Owned NAT table name is already in use')
    for route in json.loads(run('ip', '-j', '-4', 'route', 'show', 'table', 'all')):
        dst = route.get('dst', 'default')
        if dst != 'default' and ipaddress.ip_network(dst, strict=False).overlaps(ipaddress.ip_network('10.77.0.0/24')):
            raise ValueError('VPN subnet overlaps an existing route')
    if 'Status: active' not in run('ufw', 'status'):
        raise ValueError('This host-specific profile requires the inspected active UFW policy')
    before = {'ipv4_forwarding': run('sysctl', '-n', 'net.ipv4.ip_forward'),
              'ufw': run('ufw', 'status', 'numbered'), 'exit_interface': interface,
              'endpoint': endpoint, 'port': port, 'client_public': client_public}
    ROOT.mkdir(parents=True, mode=0o700)
    os.chmod(ROOT, 0o700)
    (ROOT / 'before.json').write_text(json.dumps(before, indent=2) + '\n')
    private = run('wg', 'genkey')
    public = run('wg', 'pubkey', input=private + '\n')
    transport = f'[{endpoint}]:{port}' if ':' in endpoint else f'{endpoint}:{port}'
    (ROOT / 'bootstrap-public.json').write_text(json.dumps({'endpoint': transport, 'server_public': public,
        'client_address': '10.77.0.2/32, fd77:6474:7670::2/128', 'dns': '1.1.1.1, 1.0.0.1'}, indent=2) + '\n')
    (ROOT / 'server-private').write_text(private + '\n')
    print('Prepared private server state. Networking is unchanged.')


def activate():
    before = json.loads((ROOT / 'before.json').read_text())
    if any(p.exists() or p.is_symlink() for p in (CONF, NAT, SYSCTL, UNIT, DROPIN)):
        raise ValueError('Activation resources already exist; inspect instead of overwriting')
    interface, port = before['exit_interface'], before['port']
    if any(x['ifname'] == 'dtvpn0' for x in json.loads(run('ip', '-j', 'link', 'show'))):
        raise ValueError('dtvpn0 appeared after preparation; inspect the host again')
    if run('ss', '-H', '-lun', 'sport', '=', f':{port}'):
        raise ValueError('UDP port is no longer available')
    if run('sysctl', '-n', 'net.ipv4.ip_forward') != before['ipv4_forwarding']:
        raise ValueError('Host forwarding changed after preparation; inspect the host again')
    validate_key(before['client_public'])
    private = (ROOT / 'server-private').read_text().strip()
    # No shell hooks supplied by the client. All commands and subnets are fixed.
    nat = f'''#!/bin/sh
set -eu
case "$1" in
start)
  if nft list table ip dtvpn_personal >/dev/null 2>&1; then exit 1; fi
  nft -f - <<'NFT'
table ip dtvpn_personal {{
 comment "{MARKER}"
 chain postrouting {{
  type nat hook postrouting priority srcnat; policy accept;
  ip saddr 10.77.0.2/32 oifname "{interface}" masquerade
 }}
}}
NFT
  ;;
stop)
  nft -j list table ip dtvpn_personal | python3 -c 'import json,sys; assert any(x.get("table",{{}}).get("comment")=="{MARKER}" for x in json.load(sys.stdin)["nftables"])'
  nft delete table ip dtvpn_personal
  ;;
*) exit 2;;
esac
'''
    NAT.parent.mkdir(parents=True, exist_ok=True)
    NAT.write_text(nat)
    NAT.chmod(0o700)
    CONF.parent.mkdir(mode=0o700, exist_ok=True)
    CONF.write_text(f'''[Interface]
PrivateKey = {private}
Address = 10.77.0.1/24, fd77:6474:7670::1/64
ListenPort = {port}
MTU = 1280
[Peer]
PublicKey = {before['client_public']}
AllowedIPs = 10.77.0.2/32, fd77:6474:7670::2/128
''')
    CONF.chmod(0o600)
    # Ubuntu confines wg-quick with AppArmor. Keep owned NAT management in its
    # own systemd unit rather than weakening that profile for custom hooks.
    UNIT.write_text(f'''[Unit]
Description=Duct-Tape VPN personal NAT
Before=wg-quick@dtvpn0.service
PartOf=wg-quick@dtvpn0.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart={NAT} start
ExecStop={NAT} stop
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
CapabilityBoundingSet=CAP_NET_ADMIN
RestrictAddressFamilies=AF_UNIX AF_NETLINK AF_INET AF_INET6
''')
    DROPIN.parent.mkdir(parents=True, exist_ok=True)
    DROPIN.write_text('[Unit]\nRequires=dtvpn-personal-nat.service\nAfter=dtvpn-personal-nat.service\n')
    SYSCTL.write_text('net.ipv4.ip_forward=1\n')
    run('sysctl', '-w', 'net.ipv4.ip_forward=1')
    run('ufw', 'allow', 'in', 'on', interface, 'proto', 'udp', 'to', 'any', 'port', str(port), 'comment', 'dtvpn-personal')
    run('ufw', 'allow', 'in', 'on', 'dtvpn0', 'from', '10.77.0.2', 'to', '10.77.0.1', 'comment', 'dtvpn-personal')
    run('ufw', 'route', 'allow', 'in', 'on', 'dtvpn0', 'out', 'on', interface, 'from', '10.77.0.2', 'to', 'any', 'comment', 'dtvpn-personal')
    try:
        run('systemctl', 'daemon-reload')
        run('systemctl', 'enable', '--now', 'wg-quick@dtvpn0')
    except subprocess.CalledProcessError:
        # Keep private state and rules reviewable. Stop this owned interface.
        subprocess.run(['systemctl', 'disable', '--now', 'wg-quick@dtvpn0'], capture_output=True)
        raise RuntimeError('Tunnel activation failed. Inspect systemctl status wg-quick@dtvpn0; owned files remain for review.') from None
    print('Server tunnel active. Client traffic and external reachability still require verification.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('prepare')
    p.add_argument('--client-public', required=True)
    p.add_argument('--endpoint', required=True)
    p.add_argument('--interface', required=True)
    p.add_argument('--port', type=int, default=51820)
    sub.add_parser('activate')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run through the authorized root console')
    os.umask(0o077)
    if args.command == 'prepare':
        prepare(args.client_public, args.endpoint, args.interface, args.port)
    else:
        activate()
