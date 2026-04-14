#!/bin/bash
#
# AI Gossip — macOS app release script (SPM edition)
#
# Usage:  ./scripts/release.sh <version> [release-notes.md]
# e.g.    ./scripts/release.sh 1.0
#         ./scripts/release.sh 1.0 scripts/release-notes-v1.0.md
#
# Steps:
#   1. Tool check (swift / sips / iconutil / hdiutil / fileicon / gh)
#   2. Build AppIcon.icns from resources/icon-1024.png (if stale)
#   3. swift build -c release
#   4. Assemble "AI Gossip.app" bundle (Info.plist + binary + icon)
#   5. Build DMG with Applications alias, background image, Finder layout
#   6. Git tag + push
#   7. gh release create + upload DMG

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES="$PROJECT_DIR/resources"
TMP="$PROJECT_DIR/.claude/tmp/release"
APP_NAME="AI Gossip.app"
BINARY_NAME="AIGossip"
REPO="choiyounggi/ai-gossip"
APPS_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"

VERSION="${1:-}"
NOTES_FILE="${2:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version> [release-notes.md]"
    exit 1
fi
TAG="v$VERSION"
DMG_NAME="AI-Gossip-$TAG.dmg"
DMG_FINAL="$TMP/$DMG_NAME"
DMG_RW="$TMP/rw-$DMG_NAME"
VOL_NAME="AI Gossip $TAG"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AI Gossip release $TAG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 0. Tools -----------------------------------------------------------------

echo ""
echo "🔍 [0/6] 필수 도구 확인..."
MISSING=()
for t in swift sips iconutil hdiutil fileicon gh; do
    command -v "$t" >/dev/null 2>&1 || MISSING+=("$t")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "❌ 누락: ${MISSING[*]}"
    echo "   brew install fileicon gh  # 둘 다 필요"
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "❌ gh 인증 필요: gh auth login 또는 GH_TOKEN 환경변수 설정"
    exit 1
fi
echo "✅ OK"

# 1. AppIcon.icns ----------------------------------------------------------

echo ""
echo "📐 [1/6] AppIcon.icns 빌드..."
if [ ! -f "$RESOURCES/icon-1024.png" ]; then
    echo "❌ $RESOURCES/icon-1024.png 없음. scripts/generate-icon.py 먼저 실행."
    exit 1
fi
if [ ! -f "$RESOURCES/AppIcon.icns" ] || [ "$RESOURCES/icon-1024.png" -nt "$RESOURCES/AppIcon.icns" ]; then
    bash "$SCRIPT_DIR/make-icns.sh"
else
    echo "ℹ️ AppIcon.icns 최신 상태"
fi

# 2. Swift build -----------------------------------------------------------

echo ""
echo "📦 [2/6] swift build -c release..."
mkdir -p "$TMP"
cd "$PROJECT_DIR/macos-app"
swift build -c release 2>&1 | tail -3
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="$BIN_DIR/$BINARY_NAME"
if [ ! -x "$BINARY_PATH" ]; then
    echo "❌ 바이너리 없음: $BINARY_PATH"
    exit 1
fi
echo "✅ built: $BINARY_PATH ($(du -h "$BINARY_PATH" | cut -f1))"
cd "$PROJECT_DIR"

# 3. Assemble .app bundle --------------------------------------------------

echo ""
echo "🧩 [3/6] '$APP_NAME' 번들 조립..."
APP_PATH="$TMP/$APP_NAME"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/$BINARY_NAME"
cp "$RESOURCES/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" "$RESOURCES/Info.plist" > "$APP_PATH/Contents/Info.plist"

# Ad-hoc signing lets macOS run an unsigned local build without hard Gatekeeper rejection.
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || echo "⚠️ codesign 실패 (비치명)"
echo "✅ bundle ready"

# 4. DMG -------------------------------------------------------------------

echo ""
echo "💿 [4/6] DMG 생성..."
rm -f "$DMG_RW" "$DMG_FINAL"

hdiutil create -volname "$VOL_NAME" -srcfolder "$APP_PATH" \
    -ov -format UDRW -fs HFS+ -size 60m "$DMG_RW" >/dev/null

MOUNT_DIR=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen \
    | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/' | head -1)
echo "  mount: $MOUNT_DIR"

# Applications alias + folder icon
osascript -e "tell application \"Finder\" to make new alias file at POSIX file \"$MOUNT_DIR\" to POSIX file \"/Applications\" with properties {name:\"Applications\"}" >/dev/null 2>&1 || true
fileicon set "$MOUNT_DIR/Applications" "$APPS_ICON" >/dev/null 2>&1 || true

# Background + volume icon
mkdir -p "$MOUNT_DIR/.background"
cp "$RESOURCES/dmg-background.png" "$MOUNT_DIR/.background/background.png"
cp "$RESOURCES/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR" 2>/dev/null || true

# Finder layout (best effort — AppleScript permission may prompt first run)
DISK_NAME=$(basename "$MOUNT_DIR")
osascript >/dev/null 2>&1 <<EOS || true
tell application "Finder"
    tell disk "$DISK_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 520}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set text size of theViewOptions to 14
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP_NAME" of container window to {160, 180}
        set position of item "Applications" of container window to {440, 180}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOS

chmod -Rf go-w "$MOUNT_DIR" 2>/dev/null || true
rm -rf "$MOUNT_DIR/.fseventsd" 2>/dev/null || true
sync && sleep 1
hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force >/dev/null

hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" >/dev/null
rm -f "$DMG_RW"
DMG_SIZE=$(du -h "$DMG_FINAL" | cut -f1)
echo "✅ DMG: $DMG_FINAL ($DMG_SIZE)"

# 5. Git tag ---------------------------------------------------------------

echo ""
echo "🏷️  [5/6] Git 태그..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "ℹ️ tag $TAG 이미 존재 — 건너뜀"
else
    git tag "$TAG"
    git push origin "$TAG"
    echo "✅ $TAG pushed"
fi

# 6. GitHub Release --------------------------------------------------------

echo ""
echo "🚀 [6/6] GitHub Release 업로드..."
NOTES_ARG=(--generate-notes)
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
    NOTES_ARG=(--notes-file "$NOTES_FILE")
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "ℹ️ release $TAG 존재 — 파일만 업로드"
    gh release upload "$TAG" "$DMG_FINAL" --repo "$REPO" --clobber
else
    gh release create "$TAG" "$DMG_FINAL" \
        --repo "$REPO" \
        --title "$TAG — AI Gossip" \
        "${NOTES_ARG[@]}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 릴리즈 완료"
echo "   https://github.com/$REPO/releases/tag/$TAG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
