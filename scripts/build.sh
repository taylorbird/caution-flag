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

# Build number = commit count + 100: monotonic, so newer builds always compare higher.
# The offset exists because the 2026-11-19 history rewrite (public repo) reset the
# count to ~20 while 0.1.3 had already shipped as build 26; Sparkle only offers a
# higher build. Never lower it.
BUILD_OFFSET=100
BUILD_NUMBER=$(( $(git -C "$ROOT" rev-list --count HEAD) + BUILD_OFFSET ))

xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
xcodebuild -project "$ROOT/CautionFlag.xcodeproj" -scheme CautionFlag -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' -quiet \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" ${MARKETING_VERSION:+MARKETING_VERSION=$MARKETING_VERSION} build

# actool's AppIcon.icns stops at 256 px, and launchers that read the .icns
# (Monarch) show a blank icon at larger sizes. Replace it with a full 16–1024
# set rendered from the app's own Liquid Glass icon, then re-sign: changing a
# file inside the bundle breaks Xcode's seal, and Xcode can't see this step.
swift "$ROOT/scripts/render-icns.swift" "$BUILT" "$BUILT/Contents/Resources/AppIcon.icns" \
  || echo "warning: kept actool's AppIcon.icns" >&2

# Sparkle ships helper tools inside its framework. Notarization needs every one
# signed with our Developer ID and the hardened runtime, innermost first.
SPARKLE="$BUILT/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
  for xpc in "$SPARKLE"/Versions/B/XPCServices/*.xpc(N); do
    sign --preserve-metadata=entitlements "$xpc"
  done
  [[ -e "$SPARKLE/Versions/B/Autoupdate" ]] && sign "$SPARKLE/Versions/B/Autoupdate"
  [[ -d "$SPARKLE/Versions/B/Updater.app" ]] && sign "$SPARKLE/Versions/B/Updater.app"
  sign "$SPARKLE"
fi
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$BUILT"
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
