#!/bin/zsh
# Generates the Xcode project, builds Release, and installs to /Applications.
# Usage: scripts/build.sh [--run] [--no-install]
#   --run         launch the installed app
#   --no-install  build only; the app is at $DERIVED/Build/Products/Release
#
# Install location matters: on macOS 27 status items are hosted by MenuBarAgent,
# and an app run from anywhere but /Applications gets an item Bartender can't
# see (it hides it). Same fix as Space Manager and Claude Manager.
set -euo pipefail
ROOT="${0:A:h:h}"
DERIVED="$ROOT/.build/xcode"
NAME="Caution Flag"
APP="/Applications/$NAME.app"
BUILT="$DERIVED/Build/Products/Release/$NAME.app"
IDENTITY="Developer ID Application: Taylor Bird (UFCDGSKCXB)"
RUN=0 INSTALL=1
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    --no-install) INSTALL=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Build number = commit count: monotonic, so newer builds always compare higher.
BUILD_NUMBER=$(git -C "$ROOT" rev-list --count HEAD)

xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
xcodebuild -project "$ROOT/CautionFlag.xcodeproj" -scheme CautionFlag -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' -quiet \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" ${MARKETING_VERSION:+MARKETING_VERSION=$MARKETING_VERSION} build

# actool's AppIcon.icns stops at 256 px, and launchers that read the .icns
# (Monarch) show a blank icon at larger sizes. Replace it with a full 16–1024
# set rendered from the app's own Liquid Glass icon, then re-sign: changing a
# file inside the bundle breaks Xcode's seal, and Xcode can't see this step.
if swift "$ROOT/scripts/render-icns.swift" "$BUILT" "$BUILT/Contents/Resources/AppIcon.icns"; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$BUILT"
else
  echo "warning: kept actool's AppIcon.icns" >&2
fi
codesign --verify --strict --deep "$BUILT"

(( INSTALL )) || { echo "Built $BUILT"; exit 0; }

pkill -x "$NAME" 2>/dev/null || true
pkill -x Cooldown 2>/dev/null || true
# Earlier builds were named Cooldown; a second copy confuses Launch Services,
# login items, and the Accessibility list.
rm -rf "/Applications/Cooldown.app" "$HOME/Applications/Cooldown.app"
rm -rf "$APP"
ditto "$BUILT" "$APP"
echo "Installed $APP (build $BUILD_NUMBER)"

(( RUN )) && open "$APP"
exit 0
