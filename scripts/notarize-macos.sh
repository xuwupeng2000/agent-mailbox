#!/bin/bash
# Run after a Developer ID signed build. Credentials stay in the local Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-27.0.0.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer
fi
NOTARY_PROFILE="${NOTARY_PROFILE:-agent-mailbox}"
APP="dist/Agent Mailbox.app"
ARCHIVE="Agent-Mailbox-0.1.0-macOS-universal.zip"
codesign --verify --deep --strict "$APP"
if ! codesign -dvv "$APP" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:'; then
  echo "First build with SIGNING_IDENTITY='Developer ID Application: ...'." >&2
  exit 1
fi
xcrun notarytool submit "dist/$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > dist/notarization-result.json
STATUS="$(plutil -extract status raw -o - dist/notarization-result.json)"
if [[ "$STATUS" != "Accepted" ]]; then
  cat dist/notarization-result.json
  echo "Notarization not accepted; do not publish this archive." >&2
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
echo "Notarized, stapled, and verified: dist/$ARCHIVE"
