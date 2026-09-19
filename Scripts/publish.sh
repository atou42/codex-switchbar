#!/bin/bash
# Explicitly creates a NEW PUBLIC repository. Never modifies an existing repository.
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:-codex-switchbar}"
expected_owner="atou42"
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then echo 'Invalid repository name.' >&2; exit 1; fi
python3 Scripts/check-source.py
if ! command -v gh >/dev/null 2>&1; then
  echo 'Install GitHub CLI (brew install gh), then run gh auth login. Do not paste a token into chat.' >&2
  exit 1
fi
gh auth status >/dev/null
owner="$(gh api user --jq .login)"
if [[ "$owner" != "$expected_owner" ]]; then
  echo "Signed in as $owner, not $expected_owner. Run gh auth switch --user $expected_owner first." >&2
  exit 1
fi
if gh repo view "$owner/$name" >/dev/null 2>&1; then
  echo "$owner/$name already exists. Stopping; this script never modifies an existing repository." >&2
  exit 1
fi
if [[ -e .git ]]; then
  echo 'This publication script requires a fresh source folder without .git; it will not publish existing history.' >&2
  echo 'Extract a fresh source archive, or review and publish your existing repository manually.' >&2
  exit 1
fi
git init -b main
if git remote get-url origin >/dev/null 2>&1; then
  echo 'An origin remote already exists. Stopping rather than changing it.' >&2
  exit 1
fi
# Explicit project paths only. Credentials from ~/.codex and Keychain are never added.
git add -- Package.swift README.md README_EN.md LICENSE SECURITY.md CHANGELOG.md AGENTS.md \
  .gitignore .editorconfig Sources Tests Scripts Resources docs preview .github
if ! git diff --cached --quiet; then
  git -c user.name="Codex Switch contributors" -c user.email="codex-switchbar@users.noreply.github.com" \
    commit -m "Add native macOS Codex account switcher with official usage RPC"
fi
gh repo create "$owner/$name" --public \
  --description 'A small native macOS menu bar switcher for one shared Codex environment. Keychain-backed accounts; official usage RPC; no proxy.' \
  --source=. --remote=origin --push
printf '\nPublic repository created: https://github.com/%s/%s\n' "$owner" "$name"
