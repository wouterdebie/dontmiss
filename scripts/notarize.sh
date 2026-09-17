#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool Keychain profile}"
APP="$PWD/dist/Don't Miss.app"
ARCHIVE="$PWD/dist/DontMiss-notarize.zip"
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
