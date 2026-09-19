#!/usr/bin/env python3
"""A small pre-publication check. Not a substitute for a professional secret scanner."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {'.git', '.build', '.swiftpm', 'dist', '__pycache__'}
FORBIDDEN = {'auth.json', 'accounts.json', 'transaction.json', '.env', 'config.toml'}
PATTERNS = [
    re.compile(rb'gh[pousr]_[A-Za-z0-9]{36,}'),
    re.compile(rb'github_pat_[A-Za-z0-9_]{40,}'),
    re.compile(rb'sk-proj-[A-Za-z0-9_-]{35,}'),
    re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    re.compile(rb'eyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{30,}\.[A-Za-z0-9_-]{20,}'),
]
failures = []
count = 0
for file in ROOT.rglob('*'):
    relative = file.relative_to(ROOT)
    if any(part in SKIP_DIRS for part in relative.parts):
        continue
    if file.is_symlink():
        failures.append(f'{relative}: unexpected symlink')
        continue
    if not file.is_file():
        continue
    if file.name in FORBIDDEN or file.suffix in {'.keychain', '.p12', '.pem'}:
        failures.append(f'{relative}: private-data filename')
        continue
    data = file.read_bytes()
    count += 1
    if any(pattern.search(data) for pattern in PATTERNS):
        failures.append(f'{relative}: possible secret (value intentionally not printed)')
if failures:
    print('\n'.join(failures), file=sys.stderr)
    sys.exit(1)
print(f'Checked {count} source/artifact files: no known credential files or token patterns found.')
