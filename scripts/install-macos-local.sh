#!/usr/bin/env bash
# Replace /Applications/Zeron.app with the local build in target/package/Zeron.app,
# with automatic updates off so the next release does not replace it.
# Stops the running app and engine first: every running session stops.
# The current app is backed up to ~/.zeron/backups/ as a zip.
#
# Usage: CARGO_NET_GIT_FETCH_WITH_CLI=true scripts/package-macos.sh
#        scripts/install-macos-local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$ROOT/target/package/Zeron.app"
DEST="/Applications/Zeron.app"
BACKUP_DIR="$HOME/.zeron/backups"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[[ -d "$NEW" ]] || { echo "missing $NEW: run scripts/package-macos.sh first" >&2; exit 1; }

wait_gone() {
  for _ in $(seq 1 100); do
    pgrep -f -x "$1" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  echo "$1 did not stop" >&2
  exit 1
}

echo "Quitting Zeron app"
osascript -e 'quit app "Zeron"' >/dev/null 2>&1 || true
wait_gone "$DEST/Contents/MacOS/zeron"

echo "Stopping Zeron engine"
pkill -TERM -f -x "$DEST/Contents/MacOS/Zeron Engine" || true
wait_gone "$DEST/Contents/MacOS/Zeron Engine"

if [[ -d "$DEST" ]]; then
  mkdir -p "$BACKUP_DIR"
  version="$(defaults read "$DEST/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
  backup="$BACKUP_DIR/Zeron-$version-$(date +%Y%m%d%H%M%S).zip"
  echo "Backing up $DEST to $backup"
  ditto -c -k --keepParent "$DEST" "$backup"
  rm -rf "$DEST"
fi

echo "Installing local build"
ditto "$NEW" "$DEST"
# Report-only updates: the app shows that a release exists, but does not
# download it or install it on quit (crates/update/src/lib.rs).
plutil -insert LSEnvironment -dictionary "$DEST/Contents/Info.plist" 2>/dev/null || true
plutil -replace LSEnvironment.ZERON_AUTO_UPDATE -string 0 "$DEST/Contents/Info.plist"
codesign --deep --force --entitlements "$ROOT/dist/macos/Zeron.entitlements" --sign - "$DEST"
"$LSREGISTER" -f "$DEST"

echo "Launching"
open "$DEST"
