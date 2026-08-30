#!/usr/bin/env bash
# Package an .app into the usual drag-to-Applications DMG.
#
# Shared by scripts/release.sh and the universal-build workflow so the layout a downloader sees is
# the same one the signed release ships. It only builds the image: signing, notarizing and stapling
# the container stay in release.sh, which is where the identity lives.
set -euo pipefail
APP="${1:?usage: scripts/dmg.sh <app> <dmg>}"
DMG="${2:?usage: scripts/dmg.sh <app> <dmg>}"

STAGING="$(dirname "$DMG")/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname agterm -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
