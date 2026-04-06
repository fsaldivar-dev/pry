#!/bin/bash
# Build PryApp as a macOS .app bundle
# Usage: ./scripts/build-app.sh [VERSION]

set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="Pry"
BUILD_DIR="build/app"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "==> Building PryApp v${VERSION}..."

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Build release binaries
swift build -c release

# SPM puts executables in arch-specific path
BIN_PATH="$(swift build -c release --show-bin-path)"

# Validate binaries exist before copying
if [ ! -f "${BIN_PATH}/PryApp" ]; then
    echo "ERROR: PryApp binary not found at ${BIN_PATH}/PryApp"
    exit 1
fi
if [ ! -f "${BIN_PATH}/pry" ]; then
    echo "ERROR: pry CLI binary not found at ${BIN_PATH}/pry"
    exit 1
fi

# Copy app binary
cp "${BIN_PATH}/PryApp" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Also include CLI binary
cp "${BIN_PATH}/pry" "${APP_BUNDLE}/Contents/MacOS/pry"

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>dev.fsaldivar.pry</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

echo "==> App bundle created: ${APP_BUNDLE}"
echo "    Binary: $(file "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}")"
echo "    Size: $(du -sh "${APP_BUNDLE}" | cut -f1)"
