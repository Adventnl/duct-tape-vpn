#!/usr/bin/env python3
"""Build the standalone local macOS client using Command Line Tools, without Xcode.

Requires Homebrew wireguard-tools. Bundles a private, relocatable runtime so the
installed root helper never executes tools/libraries from user-writable Homebrew.
This is a local ad-hoc build, not a notarized distribution or Network Extension.
"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / '.local/macos-personal/payload'
RUNTIME = OUT / 'runtime'
APP = OUT / 'Duct-Tape VPN.app'


def run(*args):
    return subprocess.check_output([str(x) for x in args], text=True)


def dependencies(path):
    return [line.strip().split(' (compatibility')[0] for line in run('/usr/bin/otool', '-L', path).splitlines()[1:]]


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    (RUNTIME / 'bin').mkdir(parents=True)
    (RUNTIME / 'lib').mkdir()
    source = REPO / 'clients/native/macos-personal'
    run('/usr/bin/swiftc', '-swift-version', '5', '-o', OUT / 'connection-tests',
        source / 'ConnectionState.swift', source / 'tests/ConnectionStateTests.swift')
    print(run(OUT / 'connection-tests').strip())
    (OUT / 'connection-tests').unlink()
    run('/usr/bin/swiftc', '-swift-version', '5', '-O', '-o', RUNTIME / 'duct-helper', source / 'Helper.swift')
    # Assertions stay enabled in this validation-only build.
    run('/usr/bin/swiftc', '-swift-version', '5', '-o', OUT / 'helper-tests', source / 'Helper.swift')
    print(run(OUT / 'helper-tests', 'selftest').strip())
    (OUT / 'helper-tests').unlink()
    contents = APP / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Resources').mkdir()
    run('/usr/bin/swiftc', '-swift-version', '5', '-O', '-o', contents / 'MacOS/DuctTape',
        source / 'ConnectionState.swift', source / 'App.swift')
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'DuctTape', 'CFBundleIdentifier': 'dev.ducttape.personal',
        'CFBundleName': 'Duct-Tape VPN', 'CFBundleDisplayName': 'Duct-Tape VPN',
        'CFBundleIconFile': 'DuctTape',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1.0',
        'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True,
        'NSHumanReadableCopyright': 'Duct-Tape VPN — personal development build',
    }))
    shutil.copy2(REPO / 'clients/assets/DuctTape.icns', contents / 'Resources/DuctTape.icns')
    prefix = Path(run('/opt/homebrew/bin/brew', '--prefix').strip())
    for name in ('bash', 'wg', 'wireguard-go', 'wg-quick'):
        shutil.copy2(prefix / 'bin' / name, RUNTIME / 'bin' / name)
    binaries = list((RUNTIME / 'bin').iterdir())
    pending = [p for p in binaries if p.name != 'wg-quick']
    rewritten = set()
    while pending:
        path = pending.pop()
        if path in rewritten:
            continue
        rewritten.add(path)
        for dependency in dependencies(path):
            if dependency.startswith(('/usr/lib/', '/System/Library/')):
                continue
            if not dependency.startswith(str(prefix) + '/'):
                raise RuntimeError(f'Unresolved non-system dependency: {dependency}')
            library = RUNTIME / 'lib' / Path(dependency).name
            if not library.exists():
                shutil.copy2(dependency, library)
                pending.append(library)
            target = '@loader_path/' + ('../lib/' if path.parent.name == 'bin' else '') + library.name
            run('/usr/bin/install_name_tool', '-change', dependency, target, path)
        if path.suffix == '.dylib':
            run('/usr/bin/install_name_tool', '-id', '@loader_path/' + path.name, path)
    for path in rewritten:
        run('/usr/bin/codesign', '--force', '--sign', '-', path)
        assert all(d.startswith(('/usr/lib/', '/System/Library/', '@loader_path/')) for d in dependencies(path))
    for path in RUNTIME.rglob('*'):
        if path.is_file():
            path.chmod(0o755 if path.parent.name == 'bin' or path.name == 'duct-helper' else 0o644)
    run('/usr/bin/codesign', '--force', '--sign', '-', APP)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', APP)
    # Confirm relocated Bash can launch without resolving Homebrew libraries.
    print(run(RUNTIME / 'bin/bash', '--noprofile', '--norc', '-c', 'printf "Private Bash runtime %s\\n" "$BASH_VERSION"').strip())
    print(APP)


if __name__ == '__main__':
    main()
