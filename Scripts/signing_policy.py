"""Local signing identity policy; contains no keys or account credentials."""
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import shutil
import tempfile

# Mirrors securityd's developmentOrDevIDReq. Self-signed certificates have a
# per-build cdhash partition even if their designated requirement stays stable.
DEVELOPER_REQUIREMENT = ('anchor apple generic and ('
    '(certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]) or '
    '(certificate 1[field.1.2.840.113635.100.6.2.1] and '
    '(certificate leaf[field.1.2.840.113635.100.6.1.12] or certificate leaf[field.1.2.840.113635.100.6.1.7])))')

class SigningError(ValueError):
    pass


def config_path():
    return Path.home() / 'Library/Application Support/Codex Switch/signing/identity.json'


def validate_identity(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9a-fA-F]{40}', value):
        raise SigningError('Signing identity must be one exact certificate SHA-1 fingerprint.')
    return value.upper()


def read_config(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        raise SigningError(f'Cannot open signing configuration: {path}: {error.strerror}') from error
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise SigningError('Signing configuration must be a user-owned regular file, not writable by others.')
        data = os.read(fd, 4097)
    finally:
        os.close(fd)
    if len(data) > 4096:
        raise SigningError('Signing configuration is too large; it has not been changed.')
    try:
        def unique(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise SigningError('Duplicate signing configuration key.')
                result[key] = value
            return result
        value = json.loads(data, object_pairs_hook=unique)
    except (ValueError, UnicodeError) as error:
        raise SigningError('Invalid signing configuration; it has not been changed.') from error
    if not isinstance(value, dict) or set(value) != {'schemaVersion', 'certificateSHA1'} or type(value['schemaVersion']) is not int or value['schemaVersion'] != 1:
        raise SigningError('Unsupported signing configuration; it has not been changed.')
    return validate_identity(value['certificateSHA1'])


def resolve_identity(path, ad_hoc=False):
    # lexists also catches a broken symlink; do not mistake it for first-run state.
    if os.path.lexists(path):
        identity = read_config(path)
        if ad_hoc:
            raise SigningError('A stable signing identity is configured. Refusing an ad-hoc downgrade.')
        return identity
    if ad_hoc:
        return '-'
    raise SigningError('Stable signing is not configured. Run python3 Scripts/configure-signing.py once. CI-only builds may explicitly use --ad-hoc.')


def run(*arguments):
    result = subprocess.run(arguments, text=True, capture_output=True)
    if result.returncode:
        # These commands never receive an account secret or a private-key passphrase.
        raise SigningError(f'{Path(arguments[0]).name} failed ({result.returncode}): {result.stderr.strip()}')
    return result.stdout + result.stderr


def check_available(identity):
    output = run('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning')
    identities = re.findall(r'\b[0-9A-Fa-f]{40}\b', output)
    if identity not in [entry.upper() for entry in identities]:
        raise SigningError('The configured signing key is unavailable. Restore that key; no replacement identity or ad-hoc signature will be used.')


def verify_signature(target, identity, identifier):
    requirement = f'({DEVELOPER_REQUIREMENT}) and identifier "{identifier}" and certificate leaf = H"{identity}"'
    run('/usr/bin/codesign', '--verify', '--strict', '-R', '=' + requirement, str(target))
    designated = run('/usr/bin/codesign', '-d', '-r-', str(target))
    if 'cdhash' in designated or 'designated =>' not in designated or identifier not in designated:
        raise SigningError('Signature lacks a stable application identity; do not install this build.')


def check_signer(identity):
    check_available(identity)
    # Test the actual chain, not a certificate's displayed name or a fake OU.
    with tempfile.TemporaryDirectory(prefix='codex-switch-signer-check-') as directory:
        probe = Path(directory) / 'probe'
        # Do not copy protected system-file flags onto the temporary executable.
        shutil.copyfile('/usr/bin/true', probe)
        probe.chmod(0o700)
        identifier = 'cc.atou.codex-switchbar.signer-check'
        run('/usr/bin/codesign', '--force', '--sign', identity, '--timestamp=none', '--identifier', identifier, str(probe))
        verify_signature(probe, identity, identifier)


def write_config(path, identity):
    identity = validate_identity(identity)
    content = (json.dumps({'schemaVersion': 1, 'certificateSHA1': identity}, indent=2) + '\n').encode()
    # Never replace an existing identity, even on an interrupted setup or invalid file.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as target:
        target.write(content)
        target.flush()
        os.fsync(target.fileno())
