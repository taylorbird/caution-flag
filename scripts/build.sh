#!/bin/zsh
# Generates the Xcode project and builds, in one of two identities (same pattern
# as Space Manager):
#
#   scripts/build.sh              DEV: "Caution Flag Dev.app", bundle ID
#                                 com.tbird.cautionflag.dev, no update feed. Quits
#                                 the live app (only one runs at a time, or both
#                                 would nudge the same draft), installs to
#                                 /Applications, launches. scripts/use-live.sh
#                                 switches back.
#   scripts/build.sh --release    LIVE: "Caution Flag.app", com.tbird.cautionflag,
#                                 Sparkle feed. Builds only; release.sh ships it.
#   --no-install                  DEV build without installing or launching.
#
# The two bundle IDs keep settings (UserDefaults) and the Accessibility grant
# separate. Both share ~/Library/Application Support/Caution Flag/ (drafts and
# Not heated reports), so reports from either land in one file.
#
# Install location matters: on macOS 27 status items are hosted by MenuBarAgent,
# and an app run from anywhere but /Applications gets an item Bartender can't
# see (it hides it). Same fix as Space Manager and Claude Manager.
set -euo pipefail
ROOT="${0:A:h:h}"
DERIVED="$ROOT/.build/xcode"
LIVE_NAME="Caution Flag"
LIVE_ID="com.tbird.cautionflag"
IDENTITY="Developer ID Application: Taylor Bird (UFCDGSKCXB)"
RELEASE=0 INSTALL=1
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE=1; INSTALL=0 ;;
    --no-install) INSTALL=0 ;;
    --run) ;; # old flag: dev builds always launch now
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
if (( RELEASE )); then
  NAME="$LIVE_NAME"; BUNDLE_ID="$LIVE_ID"
else
  NAME="$LIVE_NAME Dev"; BUNDLE_ID="$LIVE_ID.dev"
fi
APP="/Applications/$NAME.app"
BUILT="$DERIVED/Build/Products/Release/$NAME.app"

# Build number = commit count + 100: monotonic, so newer builds always compare higher.
# The offset exists because the 2026-11-19 history rewrite (public repo) reset the
# count to ~20 while 0.1.3 had already shipped as build 26; Sparkle only offers a
# higher build. Never lower it.
BUILD_OFFSET=100
BUILD_NUMBER=$(( $(git -C "$ROOT" rev-list --count HEAD) + BUILD_OFFSET ))

xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" --quiet
xcodebuild -project "$ROOT/CautionFlag.xcodeproj" -scheme CautionFlag -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' -quiet \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" ${MARKETING_VERSION:+MARKETING_VERSION=$MARKETING_VERSION} \
  CF_APP_NAME="$NAME" CF_BUNDLE_ID="$BUNDLE_ID" build

# A dev build must never update itself into the live release: drop the feed keys.
if (( ! RELEASE )); then
  for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$BUILT/Contents/Info.plist" 2>/dev/null || true
  done
  for key in CFBundleDisplayName CFBundleName; do
    /usr/libexec/PlistBuddy -c "Set :$key $NAME" "$BUILT/Contents/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :$key string $NAME" "$BUILT/Contents/Info.plist"
  done
fi

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

# Quit live and any older dev copy: only one Caution Flag watches drafts at a time.
for id in "$LIVE_ID" "$LIVE_ID.dev"; do
  osascript -e "quit app id \"$id\"" 2>/dev/null || true
done
for _ in {1..50}; do
  pgrep -xq "$LIVE_NAME" || pgrep -xq "$LIVE_NAME Dev" || break
  sleep 0.1
done
pkill -x "$LIVE_NAME" 2>/dev/null || true
pkill -x "$LIVE_NAME Dev" 2>/dev/null || true
pkill -x Cooldown 2>/dev/null || true
# Earlier builds were named Cooldown; a second copy confuses Launch Services,
# login items, and the Accessibility list.
rm -rf "/Applications/Cooldown.app" "$HOME/Applications/Cooldown.app"
rm -rf "$APP"
ditto "$BUILT" "$APP"
echo "Installed $APP (build $BUILD_NUMBER)"
# First dev run: start from the live settings (watched apps, sensitivity, ...).
if ! defaults read "$BUNDLE_ID" onboardingCompleted >/dev/null 2>&1; then
  defaults export "$LIVE_ID" - | defaults import "$BUNDLE_ID" - && echo "Copied live settings to $BUNDLE_ID"
fi
open "$APP"
echo "Running $NAME. Switch back with scripts/use-live.sh"
exit 0
