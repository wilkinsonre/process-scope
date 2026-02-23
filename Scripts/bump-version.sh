#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.4.0"
    exit 1
fi

VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_FILE="${PROJECT_DIR}/project.yml"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: project.yml not found at ${PROJECT_FILE}"
    exit 1
fi

# Validate version format (semver)
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: Version must be in semver format (e.g., 1.2.3)"
    exit 1
fi

# Read current build number and increment
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_FILE" | head -1 | awk '{print $2}')
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "Updating version: ${VERSION} (build ${NEW_BUILD})"

# Update MARKETING_VERSION
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"${VERSION}\"/" "$PROJECT_FILE"

# Update CURRENT_PROJECT_VERSION
sed -i '' "s/CURRENT_PROJECT_VERSION: ${CURRENT_BUILD}/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" "$PROJECT_FILE"

echo "Updated project.yml:"
echo "  MARKETING_VERSION: \"${VERSION}\""
echo "  CURRENT_PROJECT_VERSION: ${NEW_BUILD}"

# Create git tag
git tag -a "v${VERSION}" -m "Release v${VERSION}"
echo "Created git tag: v${VERSION}"

echo ""
echo "Next steps:"
echo "  git push origin main --tags    # Push tag to trigger release workflow"
