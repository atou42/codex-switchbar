#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Building the menu app requires macOS. Run swift test on Linux to test the core.' >&2
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo 'Install Apple Command Line Tools first: xcode-select --install' >&2
  exit 1
fi
architectures=("$(uname -m)")
signing_args=()
for argument in "$@"; do
  case "$argument" in
    --universal) architectures=(arm64 x86_64) ;;
    --ad-hoc) signing_args+=(--ad-hoc) ;;
    *) echo 'Usage: bash Scripts/build-app.sh [--universal] [--ad-hoc]' >&2; exit 1 ;;
  esac
done
python3 Scripts/sign-app.py --check ${signing_args[@]+"${signing_args[@]}"}
app="$PWD/dist/Codex Switch.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
binaries=()
cli_binaries=()
for arch in "${architectures[@]}"; do
  swift build --configuration release --arch "$arch" --product CodexSwitchbar
  bin="$(swift build --configuration release --arch "$arch" --show-bin-path)/CodexSwitchbar"
  binaries+=("$bin")
  swift build --configuration release --arch "$arch" --product codex-switch
  cli_binaries+=("$(dirname "$bin")/codex-switch")
done
if [[ ${#binaries[@]} == 1 ]]; then
  cp "${binaries[0]}" "$app/Contents/MacOS/CodexSwitchbar"
  cp "${cli_binaries[0]}" "$app/Contents/MacOS/codex-switch"
else
  lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/CodexSwitchbar"
  lipo -create "${cli_binaries[@]}" -output "$app/Contents/MacOS/codex-switch"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
swift Scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil --convert icns "$PWD/.build/AppIcon.iconset" --output "$app/Contents/Resources/AppIcon.icns"
python3 Scripts/sign-app.py "$app" ${signing_args[@]+"${signing_args[@]}"}
printf '\nBuilt: %s\nThis local build is not Apple-notarized.\n' "$app"
