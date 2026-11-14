#!/usr/bin/env python3
"""Render the original tape mark and platform app icons on macOS."""
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'clients/assets/app-icon.png'


def resize(size, path):
    subprocess.run(['sips', '-z', str(size), str(size), str(SOURCE), '--out', str(path)],
                   check=True, stdout=subprocess.DEVNULL)


def main():
    subprocess.run(['swift', str(REPO / 'scripts/apple/render-icon.swift'), str(SOURCE)], check=True)
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        resize(size, REPO / f'clients/app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png')
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        resize(size, REPO / f'clients/app/android/app/src/main/res/mipmap-{density}/ic_launcher.png')
    with tempfile.TemporaryDirectory() as temp:
        iconset = Path(temp) / 'DuctTape.iconset'
        iconset.mkdir()
        for size in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                resize(size * scale, iconset / f'icon_{size}x{size}{"@2x" if scale == 2 else ""}.png')
        subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(REPO / 'clients/assets/DuctTape.icns')], check=True)


if __name__ == '__main__':
    main()
