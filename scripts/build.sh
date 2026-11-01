#!/bin/zsh
# Generates the Xcode project, builds Release, and installs to ~/Applications.
# Usage: scripts/build.sh [--run]
set -euo pipefail
ROOT="${0:A:h:h}"
DERIVED="$ROOT/.build/xcode"

xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
xcodebuild -project "$ROOT/Cooldown.xcodeproj" -scheme Cooldown -configuration Release \
  -derivedDataPath "$DERIVED" -quiet build

mkdir -p "$HOME/Applications"
pkill -x Cooldown 2>/dev/null || true
rm -rf "$HOME/Applications/Cooldown.app"
cp -R "$DERIVED/Build/Products/Release/Cooldown.app" "$HOME/Applications/"
echo "Installed $HOME/Applications/Cooldown.app"

if [[ "${1:-}" == "--run" ]]; then
  open "$HOME/Applications/Cooldown.app"
fi
