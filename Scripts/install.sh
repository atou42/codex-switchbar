#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then echo 'This installer is for macOS.' >&2; exit 1; fi
# Do not kill an existing account switcher (or any Codex client).
if /usr/bin/pgrep -x CodexSwitchbar >/dev/null 2>&1; then
  echo 'Quit Codex Switch from its menu before installing an update.' >&2
  exit 1
fi
python3 Scripts/configure-signing.py
swift test
python3 -m unittest discover -s Tests/SigningTests -p 'test_*.py'
bash Scripts/build-app.sh
destination="/Applications/Codex Switch.app"
if [[ ! -w /Applications ]]; then
  echo 'Cannot write to /Applications. Ask a Mac administrator to install dist/Codex Switch.app there.' >&2
  exit 1
fi
# ditto updates the same local app path; there are no bundled third-party runtimes.
/usr/bin/ditto "dist/Codex Switch.app" "$destination"
mkdir -p "$HOME/.local/bin"
cli_link="$HOME/.local/bin/codex-switch"
cli_target="$destination/Contents/MacOS/codex-switch"
if [[ -e "$cli_link" || -L "$cli_link" ]]; then
  if [[ ! -L "$cli_link" || "$(readlink "$cli_link")" != "$cli_target" ]]; then
    echo "Cannot install CLI: $cli_link already belongs to another installation." >&2
    exit 1
  fi
else
  ln -s "$cli_target" "$cli_link"
fi
open "$destination"
printf '\nTerminal command: %s (add ~/.local/bin to PATH if needed)\n' "$cli_link"
printf '\nInstalled in: %s\nLook for the two-arrow icon in the menu bar.\n' "$destination"
