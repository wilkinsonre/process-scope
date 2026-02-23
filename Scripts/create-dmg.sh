#!/bin/bash
set -euo pipefail

APP_NAME="ProcessScope"
BUILD_DIR="build/Release"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
STAGING_DIR="build/dmg-staging"

echo "Creating DMG for ${APP_NAME}..."

# Build release
xcodebuild -project ProcessScope.xcodeproj \
    -scheme ProcessScope \
    -configuration Release \
    -derivedDataPath build \
    clean build

# Find the app
APP_PATH=$(find build -name "${APP_NAME}.app" -path "*/Release/*" | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find ${APP_NAME}.app"
    exit 1
fi

# Create staging directory
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# Create DMG
rm -f "${DMG_NAME}"
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${DMG_NAME}"

# Cleanup
rm -rf "${STAGING_DIR}"

echo "DMG created: ${DMG_NAME}"
echo "Size: $(du -h "${DMG_NAME}" | cut -f1)"
