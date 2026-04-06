#!/bin/bash
# Build PryApp as a macOS .app bundle
# Usage: ./scripts/build-app.sh [VERSION]

set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="Pry"
BUILD_DIR="build/app"

# Validate VERSION is a semver string (no injection via sed)
if ! echo "${VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
    echo "ERROR: Invalid version '${VERSION}'. Must be semver (e.g. 1.0.0)"
    exit 1
fi
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
RESOURCES_DIR="Sources/PryApp/Resources"

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

# Copy binaries
cp "${BIN_PATH}/PryApp" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${BIN_PATH}/pry" "${APP_BUNDLE}/Contents/MacOS/pry"

# Generate Info.plist from template (replace Xcode variables with actual values)
sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/dev.fsaldivar.pry/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/${VERSION}/g" \
    -e "s/\$(MARKETING_VERSION)/${VERSION}/g" \
    -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/g" \
    "${RESOURCES_DIR}/Info.plist" > "${APP_BUNDLE}/Contents/Info.plist"

# Copy asset catalog (if compiled assets exist, otherwise copy raw)
if [ -d "${BIN_PATH}/PryApp_PryApp.bundle" ]; then
    cp -R "${BIN_PATH}/PryApp_PryApp.bundle/"* "${APP_BUNDLE}/Contents/Resources/" 2>/dev/null || true
fi

# Copy entitlements (for reference, used during codesign)
cp "${RESOURCES_DIR}/PryApp.entitlements" "${APP_BUNDLE}/Contents/Resources/"

echo "==> App bundle created: ${APP_BUNDLE}"
echo "    Binary: $(file "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}")"
echo "    Size: $(du -sh "${APP_BUNDLE}" | cut -f1)"
