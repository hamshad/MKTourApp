#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$PROJECT_ROOT/android"

KEYSTORE_FILE="$ANDROID_DIR/upload-keystore.jks"
KEY_PROPERTIES_FILE="$ANDROID_DIR/key.properties"
ALIAS_NAME="upload"

if [[ -f "$KEY_PROPERTIES_FILE" ]]; then
  echo "ERROR: $KEY_PROPERTIES_FILE already exists. Refusing to overwrite."
  exit 1
fi

if [[ -f "$KEYSTORE_FILE" ]]; then
  echo "ERROR: $KEYSTORE_FILE already exists. Refusing to overwrite."
  exit 1
fi

echo "Creating Android upload keystore for Play Store signing"
echo "Keystore: $KEYSTORE_FILE"
echo "Alias:    $ALIAS_NAME"
echo

echo -n "Store password: "
read -rs STORE_PASSWORD
echo

echo -n "Key password (Enter to reuse store password): "
read -rs KEY_PASSWORD
echo

if [[ -z "$KEY_PASSWORD" ]]; then
  KEY_PASSWORD="$STORE_PASSWORD"
fi

echo
read -rp "Your name (CN) [e.g. Moksha]: " CN
read -rp "Organizational Unit (OU) [e.g. Mobile]: " OU
read -rp "Organization (O) [e.g. MK Tour]: " O
read -rp "City/Locality (L): " L
read -rp "State/Province (ST): " ST
read -rp "Country code (C) [e.g. IN]: " C

DNAME="CN=$CN, OU=$OU, O=$O, L=$L, ST=$ST, C=$C"

echo
echo "Generating keystore (this can take a few seconds)..."

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_FILE" \
  -storetype JKS \
  -alias "$ALIAS_NAME" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "$DNAME" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD"

cat > "$KEY_PROPERTIES_FILE" <<EOF
storeFile=upload-keystore.jks
storePassword=$STORE_PASSWORD
keyAlias=$ALIAS_NAME
keyPassword=$KEY_PASSWORD
EOF

chmod 600 "$KEY_PROPERTIES_FILE" || true

echo
echo "Done. Generated:"
echo "- $KEYSTORE_FILE"
echo "- $KEY_PROPERTIES_FILE"
echo
echo "Next: flutter build appbundle --release"
