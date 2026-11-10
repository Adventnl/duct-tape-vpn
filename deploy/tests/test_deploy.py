import importlib.util
import pathlib
import tempfile
import unittest
spec = importlib.util.spec_from_file_location("dtvpn", pathlib.Path(__file__).parents[1] / "dtvpn.py")
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)
class DeployTests(unittest.TestCase):
    def test_plan_validation_and_tampering(self):
        observation={"schema":1,"checks":{}}
        p=d.plan({"exit_interface":"eno1","wireguard_port":51820},observation)
        self.assertTrue(d.validate_plan(p,observation))
        p["config"]["exit_interface"]="eth0"
        with self.assertRaises(ValueError): d.validate_plan(p,observation)
    def test_staging_idempotence_backup_rollback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp)/"root"
            files={"/etc/duct-tape-vpn/test.conf":b"one"}
            first=pathlib.Path(tmp)/"first"
            d.stage(files,root,first)
            second=pathlib.Path(tmp)/"second"
            d.stage(files,root,second)
            d.rollback(root,second)
            self.assertEqual((root/"etc/duct-tape-vpn/test.conf").read_bytes(),b"one")
            d.rollback(root,first)
            self.assertFalse((root/"etc/duct-tape-vpn/test.conf").exists())
    def test_preserves_unmanaged_and_modified_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp)/"root"
            file=root/"etc/duct-tape-vpn/test.conf"
            file.parent.mkdir(parents=True)
            file.write_bytes(b"user")
            with self.assertRaises(ValueError): d.stage({"/etc/duct-tape-vpn/test.conf":b"new"},root,pathlib.Path(tmp)/"backup")
            self.assertEqual(file.read_bytes(),b"user")
    def test_symlink_escape_and_foreign_paths_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp)/"root"
            root.mkdir()
            (root/"etc").symlink_to("/tmp",target_is_directory=True)
            with self.assertRaises(ValueError):d.path_under(root,"/etc/duct-tape-vpn/file")
            with self.assertRaises(ValueError):d.path_under(root,"/etc/ssh/sshd_config")
            with self.assertRaises(ValueError):d.path_under(root,"/etc/duct-tape-vpn/../ssh/sshd_config")
    def test_render_never_uses_global_flush_or_unrestricted_nat(self):
        files=d.material({"exit_interface":"eno1","wireguard_port":51821})
        nft=files["/etc/duct-tape-vpn/firewall.nft"].decode()
        self.assertNotIn("flush ruleset",nft)
        self.assertIn('ip saddr 10.77.0.0/24 oifname "eno1" masquerade',nft)
        self.assertIn('iifname "dtvpn0" meta nfproto ipv6 drop',nft)
        with self.assertRaises(ValueError):d.material({"exit_interface":"eno1; sh","wireguard_port":1})
if __name__=="__main__":unittest.main()
