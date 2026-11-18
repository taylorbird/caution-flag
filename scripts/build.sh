#!/bin/zsh
# Generates the Xcode project, builds Release, and installs to /Applications.
# Usage: scripts/build.sh [--run]
#
# Install location matters: on macOS 27 status items are hosted by MenuBarAgent,
# and an app run from anywhere but /Applications gets an item Bartender can't
# see (it hides it). Same fix as Space Manager and Claude Manager.
set -euo pipefail
ROOT="${0:A:h:h}"
DERIVED="$ROOT/.build/xcode"
APP="/Applications/Cooldown.app"
LEGACY="$HOME/Applications/Cooldown.app"

xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
xcodebuild -project "$ROOT/Cooldown.xcodeproj" -scheme Cooldown -configuration Release \
  -derivedDataPath "$DERIVED" -quiet build

pkill -x Cooldown 2>/dev/null || true
# Older builds installed to ~/Applications; a second copy confuses Launch
# Services, login items, and the Accessibility list.
rm -rf "$LEGACY"
rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/Cooldown.app" "$APP"
echo "Installed $APP"

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
