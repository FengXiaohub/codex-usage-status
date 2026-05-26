#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CodexUsageStatus.app"
VERSION="${VERSION:-0.1.0}"
ARCH="$(uname -m)"
ZIP_NAME="CodexUsageStatus-${VERSION}-macos-${ARCH}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

"$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

(
  cd "$DIST_DIR"
  openssl dgst -sha256 -r "$ZIP_NAME" > SHA256SUMS.txt
)

echo "$ZIP_PATH"
