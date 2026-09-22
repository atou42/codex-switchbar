#!/usr/bin/env python3
"""Pin an explicitly chosen Apple-issued identity for local app updates."""
import argparse
import os
import stat
import sys
from signing_policy import SigningError, check_signer, config_path, read_config, run, validate_identity, write_config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', help='Exact SHA-1 from security find-identity -v -p codesigning')
    args = parser.parse_args()
    os.umask(0o077)
    config = config_path()
    if os.path.lexists(config):
        existing = read_config(config)
        if args.identity and validate_identity(args.identity) != existing:
            raise SigningError('A different identity is already configured; refusing to replace it.')
        check_signer(existing)
        print('Stable signing is already configured; existing identity retained.')
        return
    if not args.identity:
        print(run('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'))
        raise SigningError('Choose your Apple Development or Developer ID Application certificate above, then run: python3 Scripts/configure-signing.py --identity SHA1. No identity was selected automatically.')
    identity = validate_identity(args.identity)
    check_signer(identity)
    config.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = config.parent.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SigningError('Signing directory must be user-owned with permissions 0700, not a symlink.')
    write_config(config, identity)
    print(f'Stable signing configured: {config}')
    print('Existing private key retained in Keychain. No trust or account permissions changed.')


if __name__ == '__main__':
    try:
        main()
    except (SigningError, OSError) as error:
        sys.exit(str(error))
