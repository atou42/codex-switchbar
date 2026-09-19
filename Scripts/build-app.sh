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
if [[ "${1:-}" == --universal ]]; then
  architectures=(arm64 x86_64)
elif [[ $# -gt 0 ]]; then
  echo 'Usage: bash Scripts/build-app.sh [--universal]' >&2
  exit 1
fi
app="$PWD/dist/Codex Switch.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
binaries=()
for arch in "${architectures[@]}"; do
  swift build --configuration release --arch "$arch" --product CodexSwitchbar
  bin="$(swift build --configuration release --arch "$arch" --show-bin-path)/CodexSwitchbar"
  binaries+=("$bin")
done
if [[ ${#binaries[@]} == 1 ]]; then
  cp "${binaries[0]}" "$app/Contents/MacOS/CodexSwitchbar"
else
  lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/CodexSwitchbar"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
swift Scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil --convert icns "$PWD/.build/AppIcon.iconset" --output "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier cc.atou.codex-switchbar "$app"
codesign --verify --strict "$app"
printf '\nBuilt: %s\nThis local build is ad-hoc signed, not Apple-notarized.\n' "$app"
