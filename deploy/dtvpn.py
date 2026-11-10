#!/usr/bin/env python3
"""Inspection and file staging. Activation deliberately requires separate reviewed commands."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
OWNED = ("/etc/duct-tape-vpn/", "/etc/systemd/system/dtvpn-", "/usr/local/lib/duct-tape-vpn/")

def run(*args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=15, check=False)
        return {"code": p.returncode, "stdout": p.stdout[:131072], "stderr": p.stderr[:4096]}
    except (OSError, subprocess.TimeoutExpired) as e:
        return {"code": -1, "error": type(e).__name__}

def inspect():
    # Never read WireGuard private keys, environment values, SSH configuration or service secrets.
    commands = {
        "os": ("cat", "/etc/os-release"), "kernel": ("uname", "-r"),
        "interfaces": ("ip", "-j", "address", "show"),
        "routes4": ("ip", "-j", "route", "show", "table", "all"),
        "routes6": ("ip", "-j", "-6", "route", "show", "table", "all"),
        "rules": ("ip", "-j", "rule", "show"), "listeners": ("ss", "-H", "-lntup"),
        "nft": ("nft", "-j", "list", "ruleset"), "iptables": ("iptables-save",),
        "ufw": ("ufw", "status"), "wireguard_interfaces": ("wg", "show", "interfaces"),
        "dns": ("resolvectl", "status"), "forwarding": ("sysctl", "net.ipv4.ip_forward", "net.ipv6.conf.all.forwarding"),
        "storage": ("df", "-PT", "/", "/srv/storage"), "memory": ("free", "-b"),
        "packages": ("dpkg-query", "-W", "wireguard-tools", "nftables", "unbound", "nginx", "systemd", "openssl"),
    }
    return {"schema": 1, "observed_at": int(time.time()), "checks": {k: run(*v) for k, v in commands.items()}}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()

def material(config):
    interface = config["exit_interface"]
    if not interface or len(interface) > 15 or not all(c.isalnum() or c in "_.-" for c in interface):
        raise ValueError("invalid interface")
    port = config["wireguard_port"]
    if not isinstance(port, int) or not 1024 <= port <= 65535:
        raise ValueError("invalid UDP port")
    result = {}
    for p in sorted((HERE / "systemd").glob("dtvpn-*")):
        result["/etc/systemd/system/" + p.name] = p.read_bytes()
    for name in ("registry.json", "unbound.conf", "firewall.nft", "network.sh"):
        text = (HERE / "templates" / name).read_text()
        text = text.replace("@EXIT_INTERFACE@", interface).replace("@WIREGUARD_PORT@", str(port))
        result["/etc/duct-tape-vpn/" + name] = text.encode()
    return result

def plan(config, observation):
    files = material(config)
    return {"schema": 1, "config": config, "observation_sha256": digest(canonical(observation)),
        "files": {k: digest(v) for k, v in files.items()},
        "activation": [
            "Create dedicated dtvpn-registry and dtvpn-gateway users; public socket group dtvpn-enroll, private socket group dtvpn-admin. Gateway must not join dtvpn-admin or read registry state.",
            "Install verified binaries to /usr/local/lib/duct-tape-vpn; bootstrap via trusted local console with Owner public keys.",
            "Review and enable IPv4 forwarding only if required; preserve and record the current value. This affects the host globally and is NOT changed by staging.",
            "Review existing firewall base hooks. Integrate narrow input/forward permits in the existing policy; accept in a new nft table cannot override a foreign drop rule.",
            "Review dtvpn network.sh, reserved subnets and UDP port against fresh interfaces/routes/listeners; provision dtvpn0, owned nft table and Unbound instance.",
            "Configure TLS public enrollment ingress and rate limits using nginx-enrollment.conf.example; configure private-only admin ingress separately. Validate certificates, renewal and ports.",
            "Forward only the chosen UDP and enrollment HTTPS ports on the router after checking CGNAT/double NAT. Keep administration private.",
            "systemctl daemon-reload; enable/start dtvpn-network dtvpn-helper dtvpn-registry dtvpn-gateway dtvpn-dns after all prerequisite checks.",
            "Run docs/ACCEPTANCE.md from a remote client; verify exit, DNS, leaks, failure blocking and OFF restoration before normal use."
        ], "not_applied": ["packages", "users", "forwarding", "network", "firewall", "router", "TLS", "systemd startup"]}

def validate_plan(p, observation):
    expected = plan(p["config"], observation)
    if p != expected:
        raise ValueError("plan or inspection changed; generate and review a new plan")
    return material(p["config"])

def path_under(root, name):
    if ".." in Path(name).parts or not name.startswith("/") or not any(name.startswith(prefix) for prefix in OWNED):
        raise ValueError("unowned path")
    root = root.resolve()
    p = root / name.lstrip("/")
    for parent in [p, *p.parents]:
        if parent == root:
            break
        if parent.is_symlink():
            raise ValueError("symlink in destination")
    if not p.resolve().is_relative_to(root):
        raise ValueError("path escaped root")
    return p

def stage(files, root, backup):
    if backup.exists():
        raise ValueError("backup path already exists")
    # An unmarked existing file is never adopted or overwritten, including on repeat installation.
    manifest_path = root / "etc/duct-tape-vpn/staged-manifest.json"
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"files": {}}
    for name, body in files.items():
        p = path_under(root, name)
        if p.exists() and (name not in previous["files"] or digest(p.read_bytes()) != previous["files"][name]["installed_sha256"]):
            raise ValueError("existing unmanaged or modified file: " + name)
    backup.mkdir(parents=True, mode=0o700)
    manifest = {"schema": 1, "files": {}}
    # Back up first so a partial write can still be rolled back.
    for index, (name, body) in enumerate(files.items()):
        p = path_under(root, name)
        old = p.read_bytes() if p.exists() else None
        entry = {"installed_sha256": digest(body), "backup": str(index) if old is not None else None, "old_mode": p.stat().st_mode & 0o777 if old is not None else None}
        if old is not None:
            (backup / str(index)).write_bytes(old)
            (backup / str(index)).chmod(0o600)
        manifest["files"][name] = entry
    (backup / "manifest.json").write_text(json.dumps(manifest, indent=2))
    for name, body in files.items():
        p = path_under(root, name)
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(p.suffix + ".dtvpn-new")
        with tmp.open("xb") as f:
            os.fchmod(f.fileno(), 0o700 if name.endswith(".sh") else 0o644)
            f.write(body)
            f.flush()
            os.fsync(f.fileno())
        tmp.replace(p)
    manifest_path.write_text(json.dumps(manifest, indent=2))
    return manifest

def rollback(root, backup):
    manifest = json.loads((backup / "manifest.json").read_text())
    for name, entry in manifest["files"].items():
        p = path_under(root, name)
        if not p.exists() or digest(p.read_bytes()) != entry["installed_sha256"]:
            raise ValueError("file changed since staging; refusing rollback: " + name)
    for name, entry in manifest["files"].items():
        p = path_under(root, name)
        if entry["backup"] is None:
            p.unlink()
        else:
            p.write_bytes((backup / entry["backup"]).read_bytes())
            p.chmod(entry["old_mode"])
    (root / "etc/duct-tape-vpn/staged-manifest.json").unlink(missing_ok=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("inspect")
    p = sub.add_parser("plan")
    p.add_argument("--inspection", type=Path, required=True)
    p.add_argument("--config", type=Path, required=True)
    p = sub.add_parser("stage")
    p.add_argument("--plan", type=Path, required=True)
    p.add_argument("--inspection", type=Path, required=True)
    p.add_argument("--approval-sha256", required=True)
    p.add_argument("--root", type=Path, default=Path("/"))
    p.add_argument("--backup", type=Path, required=True)
    p = sub.add_parser("rollback")
    p.add_argument("--root", type=Path, default=Path("/"))
    p.add_argument("--backup", type=Path, required=True)
    args = parser.parse_args()
    if args.action == "inspect":
        print(json.dumps(inspect(), indent=2))
    elif args.action == "plan":
        print(json.dumps(plan(json.loads(args.config.read_text()), json.loads(args.inspection.read_text())), indent=2))
    elif args.action == "stage":
        raw = args.plan.read_bytes()
        if digest(raw) != args.approval_sha256:
            raise ValueError("approval does not match exact plan bytes")
        files = validate_plan(json.loads(raw), json.loads(args.inspection.read_text()))
        stage(files, args.root, args.backup)
        print("Files staged. No services or host networking changed. Review activation prerequisites in plan.")
    elif args.action == "rollback":
        rollback(args.root, args.backup)
        print("Staged files restored; no host networking changed.")

if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
