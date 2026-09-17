#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="$PWD/dist/Don't Miss.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DontMiss "$APP/Contents/MacOS/DontMiss"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
    echo "No CODESIGN_IDENTITY supplied; using ad-hoc signing for local development." >&2
    codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
echo "Built: $APP"
