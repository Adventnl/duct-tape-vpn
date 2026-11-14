#!/usr/bin/env python3
"""Exercise the real helper in a disposable Linux network namespace (requires root)."""
import base64
import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def run(*args, input=None):
    return subprocess.run(args, input=input, text=True, capture_output=True,
                          check=True, timeout=10).stdout.strip()


def main(binary):
    assert os.readlink('/proc/self/ns/net') != os.readlink('/proc/1/ns/net'), 'Requires isolated namespace'
    run('ip', 'link', 'add', 'dtvpn0', 'type', 'wireguard')
    private = run('wg', 'genkey')
    run('wg', 'set', 'dtvpn0', 'private-key', '/dev/stdin',
        'listen-port', '51829', 'fwmark', '12345', input=private)
    original = run('wg', 'show', 'dtvpn0', 'public-key')
    assert original != '(none)'
    retained, removed, added = [run('wg', 'pubkey', input=run('wg', 'genkey')) for _ in range(3)]
    psk = run('wg', 'genpsk')
    run('wg', 'set', 'dtvpn0', 'peer', retained, 'allowed-ips', '10.77.0.3/32',
        'endpoint', '127.0.0.1:51830', 'persistent-keepalive', '25',
        'preshared-key', '/dev/stdin', input=psk)
    run('wg', 'set', 'dtvpn0', 'peer', removed, 'allowed-ips', '10.77.0.2/32')

    def unchanged():
        assert run('wg', 'show', 'dtvpn0', 'public-key') == original, 'server key changed'
        assert run('wg', 'show', 'dtvpn0', 'listen-port') == '51829', 'listen port changed'
        assert int(run('wg', 'show', 'dtvpn0', 'fwmark'), 0) == 12345, 'routing mark changed'

    with tempfile.TemporaryDirectory(prefix='dtvpn-helper-test-') as directory:
        sock = str(Path(directory) / 'helper.sock')
        helper = subprocess.Popen([binary, '--socket', sock], stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                if Path(sock).exists():
                    break
                assert helper.poll() is None, 'helper exited'
                time.sleep(.05)

            def reconcile(peers):
                body = json.dumps({'revision': 1, 'peers': [
                    {'public_key': base64.urlsafe_b64encode(base64.b64decode(key)).decode().rstrip('='),
                     'slot': slot} for key, slot in peers]})
                connection = http.client.HTTPConnection('localhost', timeout=5)
                connection.sock = socket.socket(socket.AF_UNIX)
                connection.sock.settimeout(5)
                connection.sock.connect(sock)
                try:
                    connection.request('POST', '/reconcile', body, {'Content-Type': 'application/json'})
                    response = connection.getresponse()
                    response.read()
                    return response.status
                finally:
                    connection.close()

            for _ in range(3):
                assert reconcile([(retained, 3), (added, 6)]) == 204
                unchanged()
                assert set(run('wg', 'show', 'dtvpn0', 'peers').split()) == {retained, added}
                assert f'{retained}\t127.0.0.1:51830' in run('wg', 'show', 'dtvpn0', 'endpoints')
                assert f'{retained}\t25' in run('wg', 'show', 'dtvpn0', 'persistent-keepalive')
                assert f'{retained}\t{psk}' in run('wg', 'show', 'dtvpn0', 'preshared-keys')
                assert f'{added}\t10.77.0.6/32 fd77:6474:7670::6/128' in run('wg', 'show', 'dtvpn0', 'allowed-ips')
            assert reconcile([(retained, 1)]) == 400
            unchanged()
            assert set(run('wg', 'show', 'dtvpn0', 'peers').split()) == {retained, added}
            for _ in range(2):
                assert reconcile([]) == 204
                unchanged()
                assert not run('wg', 'show', 'dtvpn0', 'peers')
            print('PASS: repeated add/remove, invalid request, empty set; identity, port, mark and retained peer settings preserved')
        finally:
            helper.terminate()
            helper.wait(timeout=5)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--inside':
        main(sys.argv[2])
    elif len(sys.argv) == 2:
        binary = str(Path(sys.argv[1]).resolve(strict=True))
        subprocess.run(['unshare', '--net', sys.executable, str(Path(__file__).resolve()),
                        '--inside', binary], check=True)
    else:
        raise SystemExit('Usage: sudo python3 scripts/test-helper-reconcile.py PATH_TO_DUCT_HELPER')
