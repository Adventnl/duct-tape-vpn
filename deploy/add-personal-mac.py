#!/usr/bin/env python3
"""Add the owner's distinct Mac peer to the inspected personal dtvpn0 server.

Run over the trusted server console as root. Preserves the Windows peer and
existing Tailscale/UFW policies; backs up owned files before adding narrow rules.
"""
import argparse
import base64
import os
from pathlib import Path
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def activate(public):
    if len(base64.b64decode(public, validate=True)) != 32:
        raise ValueError('Expected a 32-byte public key')
    conf = Path('/etc/wireguard/dtvpn0.conf')
    nat = Path('/usr/local/lib/duct-tape-vpn/personal-nat')
    text, helper = conf.read_text(), nat.read_text()
    # This deliberately supports only the previously inspected personal layout.
    expected = '  ip saddr 10.77.0.2/32 oifname "eno1" masquerade'
    assert 'Address = 10.77.0.1/24, fd77:6474:7670::1/64' in text
    assert 'Duct-Tape VPN personal v1' in helper and expected in helper
    marker = f'PublicKey = {public}\nAllowedIPs = 10.77.0.3/32, fd77:6474:7670::3/128'
    if marker in text:
        assert public in run('wg', 'show', 'dtvpn0', 'peers')
        print('Mac peer already provisioned; no changes made.')
        return
    assert public not in text and '10.77.0.3' not in text and 'fd77:6474:7670::3' not in text
    assert '10.77.0.3' not in run('wg', 'show', 'dtvpn0', 'allowed-ips')
    assert '10.77.0.3' not in run('nft', 'list', 'table', 'ip', 'dtvpn_personal')
    assert 'Status: active' in run('ufw', 'status')
    backup = Path('/etc/duct-tape-vpn/personal/macbook-before')
    backup.mkdir(mode=0o700)
    (backup / 'dtvpn0.conf').write_text(text)
    (backup / 'personal-nat').write_text(helper)
    (backup / 'ufw.txt').write_text(run('ufw', 'status', 'numbered') + '\n')
    (backup / 'nat.txt').write_text(run('nft', '-a', 'list', 'table', 'ip', 'dtvpn_personal') + '\n')
    # No restart: the existing Windows tunnel continues running.
    run('ufw', 'allow', 'in', 'on', 'dtvpn0', 'from', '10.77.0.3', 'to', '10.77.0.1', 'comment', 'dtvpn-personal-macbook')
    run('ufw', 'route', 'allow', 'in', 'on', 'dtvpn0', 'out', 'on', 'eno1', 'from', '10.77.0.3', 'to', 'any', 'comment', 'dtvpn-personal-macbook')
    addition = '  ip saddr 10.77.0.3/32 oifname "eno1" masquerade comment "dtvpn-personal-macbook"'
    nat.write_text(helper.replace(expected, expected + '\n' + addition, 1))
    run('nft', 'add', 'rule', 'ip', 'dtvpn_personal', 'postrouting', 'ip', 'saddr', '10.77.0.3/32', 'oifname', 'eno1', 'masquerade', 'comment', '"dtvpn-personal-macbook"')
    run('wg', 'set', 'dtvpn0', 'peer', public, 'allowed-ips', '10.77.0.3/32,fd77:6474:7670::3/128')
    conf.write_text(text.rstrip() + '\n\n# Owner MacBook (separate identity)\n[Peer]\n' + marker + '\n')
    conf.chmod(0o600)
    print('Mac peer and narrow IPv4 forwarding installed; Windows peer retained. External reachability still requires verification.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--public-key', required=True)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Use the authorized root console')
    os.umask(0o077)
    activate(args.public_key)
