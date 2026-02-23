#!/bin/bash
set -euo pipefail

APP_NAME="ProcessScope"
DMG_NAME="${APP_NAME}.dmg"
BUNDLE_ID="com.processscope.app"

# Check for required environment variables
if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
    echo "Error: Set APPLE_ID and APPLE_TEAM_ID environment variables"
    echo "  export APPLE_ID=your@email.com"
    echo "  export APPLE_TEAM_ID=XXXXXXXXXX"
    exit 1
fi

if [ ! -f "${DMG_NAME}" ]; then
    echo "Error: ${DMG_NAME} not found. Run create-dmg.sh first."
    exit 1
fi

echo "Submitting ${DMG_NAME} for notarization..."

xcrun notarytool submit "${DMG_NAME}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --keychain-profile "notarization" \
    --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "${DMG_NAME}"

echo "Verifying..."
spctl --assess --type open --context context:primary-signature -v "${DMG_NAME}"

echo "Notarization complete!"
