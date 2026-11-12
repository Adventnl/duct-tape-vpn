import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


server = load('personal_server', ROOT / 'deploy/personal-server.py')
client = load('personal_client', ROOT / 'scripts/windows/prepare-personal.py')


class PersonalProfileTests(unittest.TestCase):
    def test_public_key_rejects_empty_wrong_length_and_non_base64(self):
        for value in ('', 'not-a-key', base64.b64encode(bytes(32)).decode(), base64.b64encode(b'x' * 31).decode()):
            with self.subTest(value=value), self.assertRaises(ValueError):
                server.validate_key(value)

    def test_local_identity_is_reused_and_never_printed(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            with contextlib.redirect_stdout(io.StringIO()) as output:
                client.prepare(directory)
                initial = (directory / 'client-private.key').read_text()
                public = (directory / 'client-public.txt').read_text().strip()
                client.prepare(directory)
            self.assertEqual(initial, (directory / 'client-private.key').read_text())
            self.assertNotIn(initial.strip(), output.getvalue())
            self.assertEqual(server.validate_key(public), public)

    def test_trusted_profile_has_full_routes_and_no_hooks(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            with contextlib.redirect_stdout(io.StringIO()):
                client.prepare(directory)
                bootstrap = directory / 'public.json'
                bootstrap.write_text(json.dumps({'server_public': (directory / 'client-public.txt').read_text().strip(), 'endpoint': '192.0.2.10:51820'}))
                client.prepare(directory, bootstrap)
            profile = (directory / 'DuctTape.conf').read_text()
            self.assertIn('AllowedIPs = 0.0.0.0/0, ::/0', profile)
            self.assertIn('DNS = 1.1.1.1, 1.0.0.1', profile)
            self.assertNotIn('PostUp', profile)
            self.assertNotIn('PreUp', profile)

    def test_endpoint_cannot_inject_a_profile_field(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            with contextlib.redirect_stdout(io.StringIO()):
                client.prepare(directory)
                bootstrap = directory / 'public.json'
                bootstrap.write_text(json.dumps({'server_public': (directory / 'client-public.txt').read_text().strip(), 'endpoint': '192.0.2.10:51820\nPostUp = bad'}))
                with self.assertRaises(ValueError):
                    client.prepare(directory, bootstrap)
            self.assertFalse((directory / 'DuctTape.conf').exists())


if __name__ == '__main__':
    unittest.main()
