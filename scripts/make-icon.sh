#!/bin/bash
# Developer utility using only macOS tools. The normal build uses AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-mailbox-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK_DIR"' EXIT
mkdir -p "$ICON_WORK_DIR/AppIcon.iconset"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" macos/WizardHat-source.png --out "$ICON_WORK_DIR/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" macos/WizardHat-source.png --out "$ICON_WORK_DIR/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_WORK_DIR/AppIcon.iconset" -o macos/AppIcon.icns
sips -z 1024 1024 macos/WizardHat-source.png --out ios/AgentMailbox/Assets.xcassets/AppIcon.appiconset/AppIcon.png >/dev/null
