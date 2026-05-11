#!/bin/bash
set -e
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "✗ xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "✗ xcodebuild not found. Install Xcode from the App Store."
    exit 1
fi

echo "→ Generating Xcode project…"
xcodegen generate --quiet

DERIVED_DATA_PATH="${TMPDIR:-/private/tmp}/CodexUsageBuild"

echo "→ Building CodexUsage (Release)…"
xcodebuild \
    -project CodexUsage.xcodeproj \
    -scheme CodexUsage \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_IDENTITY="-" \
    -quiet

APP_PATH=$(find "$DERIVED_DATA_PATH/Build/Products/Release" -name "CodexUsage.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "✗ Build succeeded but couldn't locate .app — inspect build/ for issues."
    exit 1
fi

rm -f CodexUsage.zip
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$APP_PATH" CodexUsage.zip

echo ""
echo "✓ CodexUsage.app is ready at $APP_PATH"
echo "✓ CodexUsage.zip is ready in $(pwd)"
echo "  → ditto -x -k CodexUsage.zip /Applications/"
