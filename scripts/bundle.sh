#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must be major.minor.patch" >&2; exit 1; }
BUILD_ARGS=(-c release --disable-automatic-resolution)
if [ -n "${BUILD_ARCH:-}" ]; then BUILD_ARGS+=(--arch "$BUILD_ARCH"); fi
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP="$PWD/dist/Don't Miss.app"
mkdir -p "$PWD/dist"
STAGING="$(mktemp -d "$PWD/dist/.bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
NEW="$STAGING/Don't Miss.app"
mkdir -p "$NEW/Contents/MacOS" "$NEW/Contents/Resources" "$NEW/Contents/Frameworks"
cp "$BIN/DontMiss" "$NEW/Contents/MacOS/DontMiss"
cp Resources/Info.plist "$NEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$NEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$NEW/Contents/Info.plist"
ditto "$BIN/Sparkle.framework" "$NEW/Contents/Frameworks/Sparkle.framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$NEW/Contents/Resources/Sparkle-LICENSE.txt"
bash scripts/sign.sh "$NEW"

if [ -e "$APP" ]; then
    [ ! -L "$APP" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "dev.wouter.dontmiss" ] \
        || { echo "Refusing to replace an unexpected bundle at $APP" >&2; exit 1; }
    mv "$APP" "$STAGING/previous.app"
fi
if ! mv "$NEW" "$APP"; then
    if [ -d "$STAGING/previous.app" ]; then mv "$STAGING/previous.app" "$APP"; fi
    echo "Failed to replace app bundle" >&2
    exit 1
fi
echo "Built: $APP"
