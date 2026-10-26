#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-27.0.0.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer
fi
if [[ ! -f macos/AppIcon.icns ]]; then
  echo "Missing macos/AppIcon.icns. Restore it or run bash scripts/make-icon.sh." >&2
  exit 1
fi
APP_VERSION="0.1.0"
RELEASE_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-mailbox-release.XXXXXX")"
trap 'rm -rf "$RELEASE_WORK_DIR"' EXIT
for ARCH in arm64 x86_64; do
  TARGET="${ARCH}-apple-macosx14.0"
  swift build -c release --triple "$TARGET"
  BIN_DIR="$(swift build -c release --triple "$TARGET" --show-bin-path)"
  cp "$BIN_DIR/AgentMailbox" "$RELEASE_WORK_DIR/AgentMailbox-$ARCH"
  cp "$BIN_DIR/mailbox" "$RELEASE_WORK_DIR/mailbox-$ARCH"
done
APP="$RELEASE_WORK_DIR/Agent Mailbox.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$RELEASE_WORK_DIR/AgentMailbox-arm64" "$RELEASE_WORK_DIR/AgentMailbox-x86_64" -output "$APP/Contents/MacOS/AgentMailbox"
lipo -create "$RELEASE_WORK_DIR/mailbox-arm64" "$RELEASE_WORK_DIR/mailbox-x86_64" -output "$APP/Contents/MacOS/mailbox"
cp README.md README.en.md AGENT_README.md CHANGELOG.md "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/docs"
cp docs/RELEASING.md "$APP/Contents/Resources/docs/RELEASING.md"
cp macos/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AgentMailbox</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.agentmailbox.desktop</string>
<key>CFBundleName</key><string>Agent Mailbox</string>
<key>CFBundleDisplayName</key><string>Agent Mailbox</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  if [[ "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
    echo "Use a Developer ID Application identity for outside-App-Store distribution." >&2
    exit 1
  fi
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP/Contents/MacOS/mailbox"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP/Contents/MacOS/mailbox"
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/mailbox" --help >/dev/null
for ARCH in arm64 x86_64; do
  lipo "$APP/Contents/MacOS/AgentMailbox" -verify_arch "$ARCH"
  lipo "$APP/Contents/MacOS/mailbox" -verify_arch "$ARCH"
done
mkdir -p dist
# Construct a fresh bundle so obsolete files cannot leak into the release.
rm -rf "dist/Agent Mailbox.app"
ditto "$APP" "dist/Agent Mailbox.app"
ARCHIVE="Agent-Mailbox-${APP_VERSION}-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
test -x "dist/Agent Mailbox.app/Contents/MacOS/mailbox"
test -f "dist/Agent Mailbox.app/Contents/Resources/AGENT_README.md"
echo "Built dist/$ARCHIVE (Apple Silicon + Intel, macOS 14+)"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Ad-hoc signed; not Apple notarized."
else
  echo "Developer ID signed. Run the notarization script before public distribution."
fi
