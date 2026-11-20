#!/bin/zsh
# Builds, notarizes, and publishes a Caution Flag release to the Homebrew tap.
# Usage: scripts/release.sh <version> [--dry-run]
#   --dry-run  build, notarize, staple, and zip only; no commit, tag, push,
#              GitHub release, or cask update. Works from any branch.
#
# The source repo is private, so the zip is attached to a GitHub release on the
# public tap repo (taylorbird/homebrew-caution-flag), and the cask points there.
# Needs: notarytool keychain profile "notary"; gh logged in as taylorbird; the
# tap cloned at $TAP_DIR (default ../homebrew-caution-flag).
set -euo pipefail
ROOT="${0:A:h:h}"
VERSION="${1:-}"
DRY=0
[[ "${2:-}" == "--dry-run" ]] && DRY=1
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "usage: scripts/release.sh <x.y.z> [--dry-run]" >&2; exit 2; }

NAME="Caution Flag"
TAP_REPO="taylorbird/homebrew-caution-flag"
TAP_DIR="${TAP_DIR:-$ROOT/../homebrew-caution-flag}"
CASK="$TAP_DIR/Casks/caution-flag.rb"
BUILT="$ROOT/.build/xcode/Build/Products/Release/$NAME.app"
DIST="$ROOT/dist"
ZIP="$DIST/CautionFlag-$VERSION.zip"
TAG="v$VERSION"

step() { print -P "%F{cyan}==>%f $*"; }
fail() { print -P "%F{red}release:%f $*" >&2; exit 1; }

# --- Preflight -------------------------------------------------------------
step "Preflight"
xcrun notarytool history --keychain-profile notary >/dev/null 2>&1 \
  || fail "notary profile missing; run 'xcrun notarytool store-credentials notary' in a real Terminal"
if (( ! DRY )); then
  [[ "$(git -C "$ROOT" branch --show-current)" == main ]] || fail "release from main"
  [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || fail "working tree not clean"
  git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG already exists"
  GH_TOKEN="$(gh auth token --user taylorbird 2>/dev/null)" || fail "gh has no token for taylorbird"
  export GH_TOKEN
  [[ -f "$CASK" ]] || fail "tap not found at $TAP_DIR"
  [[ -z "$(git -C "$TAP_DIR" status --porcelain)" ]] || fail "tap working tree not clean"
  git -C "$TAP_DIR" pull -q --ff-only
fi

# --- Version ---------------------------------------------------------------
if (( ! DRY )); then
  step "Setting version $VERSION"
  sed -i '' -E "s/^( *MARKETING_VERSION: ).*/\1\"$VERSION\"/" "$ROOT/project.yml"
  # Skip when a previous, failed run already committed this version.
  git -C "$ROOT" diff --quiet -- project.yml || git -C "$ROOT" commit -q -m "Release $TAG" -- project.yml
fi

# --- Build, notarize, staple ----------------------------------------------
step "Building"
MARKETING_VERSION="$VERSION" "$ROOT/scripts/build.sh" --release
codesign --verify --strict --deep "$BUILT"

mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$BUILT" "$ZIP"

step "Notarizing (a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --timeout 30m > "$DIST/notary-$VERSION.log" 2>&1 || true
cat "$DIST/notary-$VERSION.log"
grep -q "status: Accepted" "$DIST/notary-$VERSION.log" || fail "notarization was not accepted; see $DIST/notary-$VERSION.log"

step "Stapling"
xcrun stapler staple "$BUILT"
# Capture first: grep -q on a live pipe can SIGPIPE tee and trip pipefail.
ASSESS=$(spctl --assess --type execute --verbose=2 "$BUILT" 2>&1 || true)
print -r -- "$ASSESS"
[[ "$ASSESS" == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper does not accept the stapled app"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$BUILT" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
step "Built $ZIP ($SHA)"

(( DRY )) && { step "Dry run: stopping before tag, push, and publish"; exit 0; }

# --- Publish ---------------------------------------------------------------
step "Tagging and pushing source"
git -C "$ROOT" tag -a "$TAG" -m "Caution Flag $VERSION"
git -C "$ROOT" push -q --atomic origin main "$TAG"

step "Creating GitHub release on $TAP_REPO"
gh release create "$TAG" "$ZIP" -R "$TAP_REPO" --title "Caution Flag $VERSION" \
  --notes "Install or upgrade: \`brew install --cask taylorbird/caution-flag/caution-flag\`"

step "Updating cask and appcast"
sed -i '' -E -e "s/^( *version ).*/\1\"$VERSION\"/" -e "s/^( *sha256 ).*/\1\"$SHA\"/" "$CASK"
# Sparkle feed: sign the zip with the EdDSA key in the login Keychain, then add
# an item for this version at the top of appcast.xml on the tap.
SIGN_UPDATE="$ROOT/.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
SPARKLE_ATTRS=$("$SIGN_UPDATE" "$ZIP") || fail "sign_update failed (is the Sparkle key in the Keychain?)"
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$BUILT/Contents/Info.plist")
python3 -I "$ROOT/scripts/appcast-add.py" "$TAP_DIR/appcast.xml" "$VERSION" "$BUILD_NUMBER" \
  "https://github.com/$TAP_REPO/releases/download/$TAG/CautionFlag-$VERSION.zip" "$SPARKLE_ATTRS"
git -C "$TAP_DIR" add appcast.xml
git -C "$TAP_DIR" commit -q -m "caution-flag $VERSION" -- Casks/caution-flag.rb appcast.xml
git -C "$TAP_DIR" push -q

step "Released $VERSION. Upgrade with: brew upgrade --cask caution-flag"
