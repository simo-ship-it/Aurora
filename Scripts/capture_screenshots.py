#!/usr/bin/env python3
"""Render the real AppKit windows for both READMEs, using isolated preferences."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / '.build' / 'Screenshots'
BUNDLE = BUILD / 'AuroraScreenshots.app'


def main():
    subprocess.run(['swift', 'build', '-c', 'release'], cwd=ROOT, check=True)
    binary_dir = Path(subprocess.check_output(
        ['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=ROOT, text=True).strip())
    executable = BUNDLE / 'Contents' / 'MacOS' / 'AuroraScreenshots'
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources = BUNDLE / 'Contents' / 'Resources'
    resources.mkdir(exist_ok=True)
    info = plistlib.loads((ROOT / 'Resources' / 'Info.plist').read_bytes())
    info.update(CFBundleIdentifier='io.github.simo-ship-it.Aurora.Screenshots',
                CFBundleExecutable='AuroraScreenshots', CFBundleName='Aurora')
    (BUNDLE / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps(info))
    for translations in (ROOT / 'Resources').glob('*.lproj'):
        shutil.copytree(translations, resources / translations.name, dirs_exist_ok=True)
    sources = sorted(p for p in (ROOT / 'Sources' / 'Aurora').glob('*.swift') if p.name != 'main.swift')
    subprocess.run([
        'swiftc', '-whole-module-optimization', '-module-name', 'Aurora',
        '-I', str(binary_dir / 'Modules'), '-module-cache-path', str(BUILD / 'ModuleCache'),
        '-o', str(executable), *map(str, sources), str(ROOT / 'Scripts' / 'Screenshots' / 'main.swift'),
        *map(str, sorted((binary_dir / 'AuroraCore.build').glob('*.swift.o'))),
    ], cwd=ROOT, check=True, timeout=180)
    for language in ['en', 'it']:
        environment = os.environ.copy()
        environment.update(AURORA_SCREENSHOT_ROOT=str(ROOT), AURORA_SCREENSHOT_LANGUAGE=language)
        subprocess.run([str(executable), '-AppleLanguages', f'({language})'],
                       cwd=ROOT, env=environment, check=True, timeout=60)


if __name__ == '__main__':
    main()
