#!/bin/bash
# Package PryApp.app into a DMG
# Usage: ./scripts/package-dmg.sh [VERSION]
# Requires: build-app.sh to have been run first

set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="Pry"
BUILD_DIR="build/app"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_DIR="build/dmg"
DMG_NAME="Pry-${VERSION}.dmg"
DMG_PATH="build/${DMG_NAME}"
VOL_NAME="${APP_NAME} ${VERSION}"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "ERROR: ${APP_BUNDLE} not found. Run build-app.sh first."
    exit 1
fi

echo "==> Packaging DMG: ${DMG_NAME}..."

# Prepare DMG staging directory
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_BUNDLE}" "${DMG_DIR}/"

# Create Applications symlink for drag-to-install
ln -s /Applications "${DMG_DIR}/Applications"

# Create DMG using hdiutil (no external deps needed)
rm -f "${DMG_PATH}"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# Cleanup staging
rm -rf "${DMG_DIR}"

echo "==> DMG created: ${DMG_PATH}"
echo "    Size: $(du -sh "${DMG_PATH}" | cut -f1)"
echo ""
echo "SHA256: $(shasum -a 256 "${DMG_PATH}" | cut -d' ' -f1)"

# TODO: Code signing (requires Apple Developer ID certificate)
# codesign --deep --force --options runtime \
#   --sign "Developer ID Application: YOUR_NAME (TEAM_ID)" \
#   "${APP_BUNDLE}"

# TODO: Notarization (requires Apple Developer account)
# xcrun notarytool submit "${DMG_PATH}" \
#   --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" \
#   --wait
