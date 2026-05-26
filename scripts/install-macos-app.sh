#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/CodexUsageStatus.app"
TARGET_APP="${TARGET_APP:-/Applications/CodexUsageStatus.app}"

"$ROOT_DIR/scripts/build-macos-app.sh" >/dev/null

pkill -x CodexUsageStatus 2>/dev/null || true
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
open -n "$TARGET_APP"

echo "Installed and started $TARGET_APP"
echo "To start at login, add CodexUsageStatus.app in macOS System Settings > General > Login Items."
