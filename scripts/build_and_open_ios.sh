#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/build_and_open_ios.sh [BUILD_NUMBER]
# If BUILD_NUMBER is not provided, defaults to the pubspec build number fallback 26.
BUILD_NUMBER="${1:-26}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "Running flutter pub get..."
flutter pub get

echo "Building iOS IPA (build number $BUILD_NUMBER)..."
flutter build ipa --release --build-number "$BUILD_NUMBER"

ARCHIVE_PATH="$ROOT_DIR/build/ios/archive/Runner.xcarchive"
if [ -d "$ARCHIVE_PATH" ]; then
  echo "Opening archive in Xcode: $ARCHIVE_PATH"
  open -a Xcode "$ARCHIVE_PATH"
else
  echo "Archive not found at $ARCHIVE_PATH"
  exit 1
fi
