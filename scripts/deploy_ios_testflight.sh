#!/usr/bin/env bash
set -euo pipefail

# deploy_ios_testflight.sh
# Usage:
#  - Preferred (secure): create App Store Connect API key and set these env vars:
#      APP_STORE_ISSUER (Issuer ID)
#      APP_STORE_KEYID (Key ID)
#      APP_STORE_PRIVATE_KEY_PATH (path to .p8 file)
#    Then run: ./scripts/deploy_ios_testflight.sh
#  - Fallback (less recommended): store an app-specific password in macOS Keychain under service "app_store_password"
#      security add-generic-password -a "$USER" -s "app_store_password" -w "YOUR_APP_SPECIFIC_PASSWORD"
#    Also set APPLE_ID env var. Then run: ./scripts/deploy_ios_testflight.sh
#
# Security note: Do NOT hardcode passwords or long-lived secrets into this script.
# This script intentionally avoids embedding credentials in plaintext.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PUBSPEC=pubspec.yaml
if [ ! -f "$PUBSPEC" ]; then
  echo "pubspec.yaml not found in $REPO_ROOT"
  exit 1
fi

# Read current version (expects format: version: x.y.z+N)
version_line=$(grep '^version:' "$PUBSPEC" || true)
if [ -z "$version_line" ]; then
  echo "No version field found in pubspec.yaml"
  exit 1
fi
current_version=$(echo "$version_line" | awk '{print $2}')
if ! echo "$current_version" | grep -q '+'; then
  echo "Current version doesn't contain a build number. Appending +1."
  base_version="$current_version"
  build_number=0
else
  base_version=$(echo "$current_version" | sed -E 's/\+.*$//')
  build_number=$(echo "$current_version" | sed -E 's/.*\+([0-9]+).*$/\1/')
fi
new_build_number=$((build_number + 1))
new_version="${base_version}+${new_build_number}"

# Update pubspec.yaml
# Use perl to replace the version line in-place
perl -0777 -pe "s/^version:.*$/version: ${new_version}/m" -i.bak "$PUBSPEC"
rm -f "${PUBSPEC}.bak"

echo "Updated pubspec version: ${current_version} -> ${new_version}"

# Fetch dependencies and build
echo "Running flutter pub get..."
flutter pub get

echo "Building iOS IPA (build number ${new_build_number})..."
flutter build ipa --release --build-number "$new_build_number"

IPA_GLOB="build/ios/ipa/*.ipa"
IPA_PATH=$(ls $IPA_GLOB 2>/dev/null | tail -n 1 || true)
if [ -z "$IPA_PATH" ]; then
  echo "IPA not found in build/ios/ipa"
  exit 1
fi

# ----------------------------
# Credentials (OPTIONAL - inline values)
# ----------------------------
# For convenience you may paste secrets below. WARNING: embedding secrets in files
# is insecure. Prefer setting env vars or using the macOS Keychain.

# Inline App Store Connect API key values (Issuer ID, Key ID)
INLINE_APP_STORE_ISSUER=""   # e.g. "YOUR_ISSUER_ID"
INLINE_APP_STORE_KEYID=""    # e.g. "YOUR_KEY_ID"
# If you have the .p8 private key content, paste it here (PEM contents).
INLINE_APP_STORE_PRIVATE_KEY_CONTENT="" # multiline allowed

# Inline Apple ID + app-specific password (less recommended)
INLINE_APPLE_ID="yousuf@mokshasolutions.com"                 # e.g. "you@company.com"
INLINE_APP_SPECIFIC_PASSWORD=""    # app-specific password

# Team ID for Xcode signing (optional)
INLINE_TEAM_ID="N9CH3CKB69"

# If inline private key content provided, write to a temp file and use it
if [ -n "${INLINE_APP_STORE_PRIVATE_KEY_CONTENT}" ] && [ -z "${APP_STORE_PRIVATE_KEY_PATH-}" ]; then
  TMP_P8_PATH="/tmp/AuthKey_${INLINE_APP_STORE_KEYID:-key}.p8"
  printf "%s" "$INLINE_APP_STORE_PRIVATE_KEY_CONTENT" > "$TMP_P8_PATH"
  chmod 600 "$TMP_P8_PATH"
  APP_STORE_PRIVATE_KEY_PATH="$TMP_P8_PATH"
  trap 'rm -f "$TMP_P8_PATH"' EXIT
fi

# Prefer inline values if provided
if [ -n "${INLINE_APP_STORE_ISSUER}" ]; then
  APP_STORE_ISSUER="${APP_STORE_ISSUER:-$INLINE_APP_STORE_ISSUER}"
fi
if [ -n "${INLINE_APP_STORE_KEYID}" ]; then
  APP_STORE_KEYID="${APP_STORE_KEYID:-$INLINE_APP_STORE_KEYID}"
fi
if [ -n "${INLINE_APPLE_ID}" ]; then
  APPLE_ID="${APPLE_ID:-$INLINE_APPLE_ID}"
fi
if [ -n "${INLINE_APP_SPECIFIC_PASSWORD}" ]; then
  APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-$INLINE_APP_SPECIFIC_PASSWORD}"
fi
if [ -n "${INLINE_TEAM_ID}" ]; then
  TEAM_ID="${TEAM_ID:-$INLINE_TEAM_ID}"
fi

# Upload to App Store Connect
# Preferred method: App Store Connect API Key (Issuer & Key ID). xcrun altool
# accepts --apiKey/--apiIssuer. If those are set (via env or inline), use them.
if [ -n "${APP_STORE_ISSUER-}" ] && [ -n "${APP_STORE_KEYID-}" ]; then
  echo "Uploading using App Store Connect API key (env or inline)."
  xcrun altool --upload-app --type ios -f "$IPA_PATH" --apiKey "$APP_STORE_KEYID" --apiIssuer "$APP_STORE_ISSUER"
  UPLOAD_EXIT=$?
elif [ -n "${APP_SPECIFIC_PASSWORD-}" ] && [ -n "${APPLE_ID-}" ]; then
  echo "Uploading using app-specific password provided via inline or env var."
  xcrun altool --upload-app --type ios -f "$IPA_PATH" -u "$APPLE_ID" -p "$APP_SPECIFIC_PASSWORD"
  UPLOAD_EXIT=$?
elif security find-generic-password -s "app_store_password" >/dev/null 2>&1 && [ -n "${APPLE_ID-}" ]; then
  echo "Uploading using app-specific password stored in Keychain (service: app_store_password)."
  APP_SPECIFIC_PASSWORD=$(security find-generic-password -s "app_store_password" -w)
  xcrun altool --upload-app --type ios -f "$IPA_PATH" -u "$APPLE_ID" -p "$APP_SPECIFIC_PASSWORD"
  UPLOAD_EXIT=$?
else
  echo "No upload credentials found. Provide App Store Connect API key env vars (APP_STORE_ISSUER, APP_STORE_KEYID)"
  echo "or store an app-specific password in Keychain with:"
  echo "  security add-generic-password -a \"$USER\" -s \"app_store_password\" -w \"YOUR_APP_SPECIFIC_PASSWORD\""
  echo "or set INLINE_APPLE_ID/INLINE_APP_SPECIFIC_PASSWORD at the top of this script (not recommended)."
  exit 1
fi

if [ "$UPLOAD_EXIT" -eq 0 ]; then
  echo "Upload successful."
else
  echo "Upload failed with exit code $UPLOAD_EXIT"
  exit $UPLOAD_EXIT
fi

# Open archive in Organizer for manual distribution if desired
ARCHIVE_PATH=build/ios/archive/Runner.xcarchive
if [ -d "$ARCHIVE_PATH" ]; then
  echo "Opening archive in Xcode Organizer: $ARCHIVE_PATH"
  open "$ARCHIVE_PATH"
else
  echo "Archive not found at $ARCHIVE_PATH"
fi
