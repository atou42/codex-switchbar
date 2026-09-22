#!/usr/bin/env python3
"""Prove changed builds retain access to one isolated synthetic Keychain item."""
import argparse
from pathlib import Path
import subprocess
import shutil
import tempfile
import uuid
import hashlib

ROOT = Path(__file__).resolve().parent.parent

def run(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--identity', required=True, help='Certificate SHA-1, or - to reproduce the ad-hoc failure')
    args = parser.parse_args()
    service = 'cc.atou.codex-switchbar.signing-test.' + str(uuid.uuid4())
    root = Path(tempfile.mkdtemp(prefix='codex-switch-signing-test-'))
    passed = False
    try:
        variants = []
        for index in range(3):
            source = root / f'probe{index}.swift'
            source.write_text((ROOT / 'Tests/SigningTests/KeychainProbe.swift').read_text() + f'\n// Build {index}\n')
            executable = root / f'probe{index}'
            # Different embedded build data ensures different executable content.
            source.write_text(f'let signingTestBuild = "build-{index}"\n' + source.read_text())
            run('swiftc', str(source), '-o', str(executable))
            identifier = 'cc.atou.codex-switchbar.signing-probe' + ('.other' if index == 2 else '')
            run('codesign', '--force', '--sign', args.identity, '--timestamp=none', '--identifier', identifier, str(executable))
            run('codesign', '--verify', '--strict', str(executable))
            requirement = run('codesign', '-d', '-r-', str(executable))
            (root / f'requirement{index}.txt').write_text(requirement.stdout + requirement.stderr)
            variants.append(executable)
        assert hashlib.sha256(variants[0].read_bytes()).digest() != hashlib.sha256(variants[1].read_bytes()).digest(), 'Test builds must differ'
        installed = root / 'installed-probe'
        def install(index):
            # Replace the inode at a stable install path, as a real app update does.
            staged = root / 'staged-probe'
            shutil.copy2(variants[index], staged)
            staged.replace(installed)
        created = False
        try:
            install(0)
            run(str(installed), 'write', service)
            created = True
            run(str(installed), 'read', service)
            install(1)
            upgraded = run(str(installed), 'read', service, check=False)
            print('Changed build, same identity: ' + upgraded.stdout.strip())
            assert upgraded.returncode == 0, 'Updated build cannot read the synthetic item without a prompt'
            install(2)
            denied = run(str(installed), 'read', service, check=False)
            print('Different app identifier: ' + denied.stdout.strip())
            assert denied.returncode == 1 and denied.stdout.strip() in ('-25293', '-25308'), 'A different app must be refused by Keychain, not crash or read a missing item'
        finally:
            if created:
                install(0)
                run(str(installed), 'delete', service)
        passed = True
        print('PASS: changed build retained access, different app was refused; UI disabled throughout; synthetic item removed.')
    finally:
        if passed:
            shutil.rmtree(root)
        else:
            print(f'Failed test artifacts preserved: {root}')

if __name__ == '__main__':
    main()
