#!/usr/bin/env python3
"""Sign with the pinned local identity, failing rather than changing app identity."""
import argparse
from pathlib import Path
import sys
from signing_policy import SigningError, check_available, config_path, resolve_identity, run, verify_signature


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', nargs='?', type=Path)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--ad-hoc', action='store_true', help='Explicit disposable CI build, only without a configured stable identity')
    args = parser.parse_args()
    identity = resolve_identity(config_path(), args.ad_hoc)
    if identity != '-':
        check_available(identity)
    if args.check:
        return
    if args.app is None:
        parser.error('app is required unless --check is used')
    for target, identifier in [(args.app / 'Contents/MacOS/codex-switch', 'cc.atou.codex-switchbar.cli'),
                               (args.app, 'cc.atou.codex-switchbar')]:
        run('/usr/bin/codesign', '--force', '--sign', identity, '--timestamp=none', '--identifier', identifier, str(target))
        if identity == '-':
            run('/usr/bin/codesign', '--verify', '--strict', str(target))
        else:
            verify_signature(target, identity, identifier)
    print('Signed with the pinned local identity.' if identity != '-' else 'Explicit ad-hoc CI build; not suitable for preserving Keychain authorization across updates.')

if __name__ == '__main__':
    try:
        main()
    except (SigningError, OSError) as error:
        sys.exit(str(error))
