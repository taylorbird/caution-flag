#!/bin/zsh
# Switch back from the dev build to the live (Homebrew/Sparkle) app: quit
# "Caution Flag Dev", then open "Caution Flag" from /Applications.
set -euo pipefail

osascript -e 'quit app id "com.tbird.cautionflag.dev"' 2>/dev/null || true
for _ in {1..50}; do
  pgrep -xq "Caution Flag Dev" || break
  sleep 0.1
done
pkill -x "Caution Flag Dev" 2>/dev/null || true
open -b com.tbird.cautionflag
echo "Live Caution Flag running."
