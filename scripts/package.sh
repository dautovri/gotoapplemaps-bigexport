#!/bin/bash
# Local DMG build — signs with Developer ID, notarizes, staples
# Usage: ./scripts/package.sh 1.0.1
set -e

VERSION="${1:-1.0.0}"
TEAM="27EZNUVV57"
SIGN_ID="Developer ID Application: Ruslan Dautov ($TEAM)"
ARCHIVE="/tmp/BigExport.xcarchive"
EXPORT="/tmp/BigExport-export"
DMG="BigExport-$VERSION.dmg"

echo "▶ Generating project..."
xcodegen generate

echo "▶ Archiving $VERSION..."
xcodebuild -project BigExport.xcodeproj \
  -scheme BigExport \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=$SIGN_ID" \
  DEVELOPMENT_TEAM="$TEAM" \
  MARKETING_VERSION="$VERSION"

echo "▶ Exporting .app..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist ExportOptions.plist

echo "▶ Creating DMG..."
npm list -g create-dmg &>/dev/null || npm install -g create-dmg
create-dmg \
  --overwrite \
  --dmg-title "BigExport $VERSION" \
  "$EXPORT/BigExport.app" \
  /tmp/
mv /tmp/BigExport*.dmg "$DMG" 2>/dev/null || true

echo "▶ Notarizing..."
xcrun notarytool submit "$DMG" \
  --keychain-profile "notarytool" \
  --wait
xcrun stapler staple "$DMG"

echo "✅ Done: $DMG"
echo "SHA256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
