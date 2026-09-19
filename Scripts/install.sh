#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then echo 'This installer is for macOS.' >&2; exit 1; fi
# Do not kill an existing account switcher (or any Codex client).
if /usr/bin/pgrep -x CodexSwitchbar >/dev/null 2>&1; then
  echo 'Quit Codex Switch from its menu before installing an update.' >&2
  exit 1
fi
swift test
bash Scripts/build-app.sh
mkdir -p "$HOME/Applications"
destination="$HOME/Applications/Codex Switch.app"
# ditto updates the same local app path; there are no bundled third-party runtimes.
/usr/bin/ditto "dist/Codex Switch.app" "$destination"
open "$destination"
printf '\nInstalled in: %s\nLook for the two-arrow icon in the menu bar.\n' "$destination"
