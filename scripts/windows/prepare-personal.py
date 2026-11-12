"""Generate local WireGuard keys and a profile from trusted server public data.

Use an owner-only directory outside the repository. Never print private material.
Requires the cryptography package in a task-local Python environment.
"""
import argparse
import base64
import ipaddress
import json
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, PublicFormat, NoEncryption


def prepare(directory, bootstrap=None):
    directory = directory.resolve(strict=True)
    private_path = directory / 'client-private.key'
    if private_path.exists():
        raw = base64.b64decode(private_path.read_text().strip(), validate=True)
        private = X25519PrivateKey.from_private_bytes(raw)
    else:
        private = X25519PrivateKey.generate()
        raw = private.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
        with private_path.open('x') as f:
            f.write(base64.b64encode(raw).decode() + '\n')
    public = private.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    (directory / 'client-public.txt').write_text(base64.b64encode(public).decode() + '\n')
    if bootstrap:
        data = json.loads(bootstrap.read_text())
        server = base64.b64decode(data['server_public'], validate=True)
        if len(server) != 32 or server == bytes(32):
            raise ValueError('Invalid server public key')
        endpoint = data['endpoint']
        host, port = endpoint.rsplit(':', 1)
        ipaddress.ip_address(host.strip('[]'))
        if not port.isdecimal() or not 1024 <= int(port) <= 65535:
            raise ValueError('Invalid endpoint port')
        text = ('[Interface]\nPrivateKey = ' + base64.b64encode(raw).decode() + '\n'
                'Address = 10.77.0.2/32, fd77:6474:7670::2/128\n'
                'DNS = 1.1.1.1, 1.0.0.1\nMTU = 1280\n\n'
                '[Peer]\nPublicKey = ' + data['server_public'] + '\n'
                'Endpoint = ' + endpoint + '\nAllowedIPs = 0.0.0.0/0, ::/0\nPersistentKeepalive = 25\n')
        (directory / 'DuctTape.conf').write_text(text)
    print('Local key material prepared. Private material was not printed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--bootstrap', type=Path)
    args = parser.parse_args()
    prepare(args.directory, args.bootstrap)
