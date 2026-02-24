#!/bin/bash
set -euo pipefail

APP_NAME="ProcessScope"
BUILD_DIR="build/Release"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
STAGING_DIR="build/dmg-staging"
SKIP_BUILD=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
    esac
done

echo "Creating DMG for ${APP_NAME}..."

# Build release (unless --skip-build is passed, e.g. from CI)
if [ "$SKIP_BUILD" = false ]; then
    xcodebuild -project ProcessScope.xcodeproj \
        -scheme ProcessScope \
        -configuration Release \
        -derivedDataPath build \
        clean build
fi

# Find the app
APP_PATH=$(find build -name "${APP_NAME}.app" -path "*/Release/*" | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find ${APP_NAME}.app"
    exit 1
fi

# Code sign the app with Developer ID if identity is available
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "Signing app with: ${CODESIGN_IDENTITY}"
    codesign --deep --force --verify --verbose \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        "$APP_PATH"
fi

# Create staging directory
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# Copy volume icon from app icon
ICNS_PATH="${APP_PATH}/Contents/Resources/AppIcon.icns"
if [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "${STAGING_DIR}/.VolumeIcon.icns"
fi

# Create read-write DMG first (so we can set custom icon flag)
rm -f "${DMG_NAME}" "${DMG_NAME}.rw.dmg"
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDRW \
    "${DMG_NAME}.rw.dmg"

# Set custom icon flag on the volume
MOUNT_DIR=$(mktemp -d)
hdiutil attach "${DMG_NAME}.rw.dmg" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi
hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR" 2>/dev/null || true

# Convert to compressed read-only DMG
hdiutil convert "${DMG_NAME}.rw.dmg" -format UDZO -o "${DMG_NAME}"
rm -f "${DMG_NAME}.rw.dmg"

# Code sign the DMG if identity is available
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "Signing DMG with: ${CODESIGN_IDENTITY}"
    codesign --force --verify --verbose \
        --sign "$CODESIGN_IDENTITY" \
        "${DMG_NAME}"
fi

# Cleanup
rm -rf "${STAGING_DIR}"

# Output build info
DMG_SHA256=$(shasum -a 256 "${DMG_NAME}" | awk '{print $1}')
echo ""
echo "DMG created: ${DMG_NAME}"
echo "Size: $(du -h "${DMG_NAME}" | cut -f1)"
echo "SHA-256: ${DMG_SHA256}"
