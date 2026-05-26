#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/macos/CodexUsageStatus"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CodexUsageStatus.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
VERSION="${VERSION:-0.1.0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

swift build \
  --package-path "$SWIFT_DIR" \
  -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$SWIFT_DIR/.build/release/CodexUsageStatus" "$MACOS_DIR/CodexUsageStatus"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsageStatus</string>
  <key>CFBundleIdentifier</key>
  <string>dev.local.CodexUsageStatus</string>
  <key>CFBundleName</key>
  <string>Codex Usage Status</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__VERSION__</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>MIT</string>
</dict>
</plist>
PLIST

/usr/bin/sed -i '' "s/__VERSION__/$VERSION/g" "$CONTENTS_DIR/Info.plist"

codesign --force --sign "$CODESIGN_IDENTITY" "$APP_DIR" >/dev/null

echo "$APP_DIR"
