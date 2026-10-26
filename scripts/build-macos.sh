#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-27.0.0.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer
fi
if [[ ! -f macos/AppIcon.icns ]]; then
  echo "Missing macos/AppIcon.icns. Restore the checked-in icon before building." >&2
  exit 1
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Agent Mailbox.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
DEST="$APP/Contents/MacOS/AgentMailbox"
if [[ -e "$DEST" ]]; then
  rm -f "$DEST" || mv "$DEST" "$DEST.previous"
fi
cp "$BIN_DIR/AgentMailbox" "$DEST"
cp "$BIN_DIR/mailbox" "$APP/Contents/MacOS/mailbox"
# Older packages included a Python client; the native app no longer needs it.
rm -f "$APP/Contents/Resources/agent_mailbox.py"
cp README.md "$APP/Contents/Resources/README.md"
cp README.en.md "$APP/Contents/Resources/README.en.md"
cp AGENT_README.md "$APP/Contents/Resources/AGENT_README.md"
cp macos/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AgentMailbox</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.agentmailbox.desktop</string>
<key>CFBundleName</key><string>Agent Mailbox</string>
<key>CFBundleDisplayName</key><string>Agent Mailbox</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/MacOS/mailbox"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/mailbox" --help >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Agent-Mailbox-macOS.zip
shasum -a 256 dist/Agent-Mailbox-macOS.zip > dist/SHA256SUMS.txt
test -x "$APP/Contents/MacOS/mailbox"
test -f "$APP/Contents/Resources/AppIcon.icns"
test -f "$APP/Contents/Resources/AGENT_README.md"
echo "Built $APP"
echo "Ad-hoc signature only. This build is not notarized."
