#!/usr/bin/env python3
"""Verifiche AppKit in un bundle con preferenze e documenti di prova separati."""
import os
import pathlib
import plistlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / '.build' / 'AppChecks'
BUNDLE = BUILD / 'AuroraAppCheck.app'


def main():
    subprocess.run(['swift', 'build', '-c', 'release'], cwd=ROOT, check=True)
    binary_dir = pathlib.Path(subprocess.check_output(
        ['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=ROOT, text=True).strip())
    executable = BUNDLE / 'Contents' / 'MacOS' / 'AuroraAppCheck'
    executable.parent.mkdir(parents=True, exist_ok=True)
    info = plistlib.loads((ROOT / 'Resources' / 'Info.plist').read_bytes())
    info.update(CFBundleIdentifier='io.github.simo-ship-it.Aurora.AppCheck',
                CFBundleExecutable='AuroraAppCheck', CFBundleName='AuroraAppCheck')
    (BUNDLE / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps(info))
    sources = sorted(p for p in (ROOT / 'Sources' / 'Aurora').glob('*.swift') if p.name != 'main.swift')
    command = ['swiftc', '-whole-module-optimization', '-module-name', 'Aurora',
               '-I', str(binary_dir / 'Modules'), '-module-cache-path', str(BUILD / 'ModuleCache'),
               '-o', str(executable), *map(str, sources), str(ROOT / 'Tests' / 'AppKit' / 'main.swift'),
               *map(str, sorted((binary_dir / 'AuroraCore.build').glob('*.swift.o')))]
    subprocess.run(command, cwd=ROOT, check=True, timeout=180)
    environment = os.environ.copy()
    environment['AURORA_APP_CHECK_ROOT'] = str(BUILD)
    # I percorsi passano nell'ambiente: argomenti posizionali verrebbero
    # interpretati da AppKit come documenti da aprire all'avvio.
    subprocess.run([str(executable)], cwd=ROOT, env=environment, check=True, timeout=60)


if __name__ == '__main__':
    main()
