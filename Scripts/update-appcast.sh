#!/bin/bash
set -euo pipefail

if [ $# -lt 3 ]; then
    echo "Usage: $0 <dmg-path> <version> <download-url>"
    echo "Example: $0 ProcessScope.dmg 0.3.0 https://github.com/.../ProcessScope.dmg"
    exit 1
fi

DMG_PATH="$1"
VERSION="$2"
DOWNLOAD_URL="$3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APPCAST_FILE="${PROJECT_DIR}/docs/appcast.xml"

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found at ${DMG_PATH}"
    exit 1
fi

# Get file size
FILE_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH" 2>/dev/null)

# Generate EdDSA signature if key is available
EDDSA_SIGNATURE=""
if [ -n "${SPARKLE_EDDSA_KEY:-}" ]; then
    # Write key to temp file for sign_update
    KEY_FILE=$(mktemp)
    echo "$SPARKLE_EDDSA_KEY" > "$KEY_FILE"
    EDDSA_SIGNATURE=$(./bin/sign_update "$DMG_PATH" -f "$KEY_FILE" 2>/dev/null || \
                      xcrun -sdk macosx swift run --package-path .build/sparkle sign_update "$DMG_PATH" -f "$KEY_FILE" 2>/dev/null || \
                      echo "")
    rm -f "$KEY_FILE"

    if [ -z "$EDDSA_SIGNATURE" ]; then
        echo "Warning: Could not generate EdDSA signature. Sparkle sign_update not found."
        echo "Download from: https://github.com/sparkle-project/Sparkle/releases"
    fi
fi

# Get current date in RFC 2822 format
PUB_DATE=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")

# Build the signature attribute
SIGNATURE_ATTR=""
if [ -n "$EDDSA_SIGNATURE" ]; then
    SIGNATURE_ATTR="sparkle:edSignature=\"${EDDSA_SIGNATURE}\""
fi

# Create new item entry
NEW_ITEM="        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <enclosure
                url=\"${DOWNLOAD_URL}\"
                length=\"${FILE_SIZE}\"
                type=\"application/octet-stream\"
                ${SIGNATURE_ATTR}
            />
        </item>"

# Insert new item before closing </channel> tag
if [ -f "$APPCAST_FILE" ]; then
    # Insert before </channel>
    sed -i '' "s|    </channel>|${NEW_ITEM}\n    </channel>|" "$APPCAST_FILE"
else
    echo "Error: appcast.xml not found at ${APPCAST_FILE}"
    echo "Creating initial appcast.xml..."
    mkdir -p "$(dirname "$APPCAST_FILE")"
    cat > "$APPCAST_FILE" << XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>ProcessScope Updates</title>
        <link>https://github.com/wilkinsonre/process-scope</link>
        <description>ProcessScope update feed</description>
        <language>en</language>
${NEW_ITEM}
    </channel>
</rss>
XMLEOF
fi

echo "Appcast updated: ${APPCAST_FILE}"
echo "  Version: ${VERSION}"
echo "  Size: ${FILE_SIZE} bytes"
echo "  URL: ${DOWNLOAD_URL}"
if [ -n "$EDDSA_SIGNATURE" ]; then
    echo "  Signature: present"
else
    echo "  Signature: none (set SPARKLE_EDDSA_KEY to sign)"
fi
