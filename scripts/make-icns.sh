#!/bin/bash
# Build AppIcon.icns from resources/icon-1024.png using sips + iconutil.
#
# Output: resources/AppIcon.icns
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR/resources/icon-1024.png"
OUT_ICNS="$PROJECT_DIR/resources/AppIcon.icns"
ICONSET="$PROJECT_DIR/.claude/tmp/AppIcon.iconset"

if [ ! -f "$SRC" ]; then
    echo "❌ $SRC not found. Run: python3 scripts/generate-icon.py first."
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Apple-required sizes for a full iconset. sips resamples from the 1024
# master — good enough quality for a demo app.
declare -a sizes=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for entry in "${sizes[@]}"; do
    size="${entry%%:*}"
    name="${entry##*:}"
    sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
echo "✅ wrote $OUT_ICNS ($(du -h "$OUT_ICNS" | cut -f1))"
