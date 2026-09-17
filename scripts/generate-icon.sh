#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || {
    echo "Icon regeneration requires rsvg-convert (Homebrew: librsvg)." >&2
    exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"

rsvg-convert --width 1024 --height 1024 Resources/AppIcon.svg --output "$WORK/AppIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$WORK/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$ICONSET" --output "$WORK/AppIcon.icns"
cp "$WORK/AppIcon.png" Resources/AppIcon.png
cp "$WORK/AppIcon.icns" Resources/AppIcon.icns
for name in DontMissTemplate DontMissAttentionTemplate; do
    for scale in 1 2 3; do
        suffix=""
        if [ "$scale" -gt 1 ]; then suffix="@${scale}x"; fi
        pixels=$((18 * scale))
        rsvg-convert --width "$pixels" --height "$pixels" "Resources/menubar/$name.svg" \
            --output "$WORK/$name$suffix.png"
        cp "$WORK/$name$suffix.png" "Resources/menubar/$name$suffix.png"
    done
done
echo "Generated app icon and monochrome menu-bar icons at 1x, 2x and 3x."
