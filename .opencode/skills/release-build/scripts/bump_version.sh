#!/usr/bin/env bash
# Bump pubspec version (patch +1, build +1), regenerate Generated.xcconfig, verify.
# Usage: bump_version.sh            # auto patch bump
#        bump_version.sh 1.2.0+57  # explicit version
set -euo pipefail

cd "$(dirname "$0")/../../../.."
PUBSPEC="pubspec.yaml"

if [[ ! -f "$PUBSPEC" ]]; then
  echo "FAIL: $PUBSPEC not found" >&2
  exit 1
fi

CURRENT="$(grep -m1 -E '^version:' "$PUBSPEC" | awk '{print $2}')"

if [[ -n "${1:-}" ]]; then
  NEW="$1"
else
  NAME="${CURRENT%%+*}"
  BUILD="${CURRENT##*+}"
  MAJOR="${NAME%%.*}"
  REST="${NAME#*.}"
  MINOR="${REST%%.*}"
  PATCH="${REST##*.}"
  NEW="${MAJOR}.${MINOR}.$((PATCH + 1))+$((BUILD + 1))"
fi

python3 - "$PUBSPEC" "$NEW" <<'PY'
import re, sys
path, new = sys.argv[1], sys.argv[2]
src = open(path).read()
out, n = re.subn(r'(?m)^version:\s*\S+\s*$', 'version: ' + new, src, count=1)
if n != 1:
    sys.exit('FAIL: could not rewrite version line')
open(path, 'w').write(out)
PY

echo "pubspec: $CURRENT -> $NEW"

rm -f ios/Flutter/Generated.xcconfig
flutter pub get >/dev/null 2>&1 || true

EXPECT_NAME="${NEW%%+*}"
EXPECT_BUILD="${NEW##*+}"
GOT_NAME="$(grep -m1 '^FLUTTER_BUILD_NAME=' ios/Flutter/Generated.xcconfig | cut -d= -f2)"
GOT_BUILD="$(grep -m1 '^FLUTTER_BUILD_NUMBER=' ios/Flutter/Generated.xcconfig | cut -d= -f2)"

if [[ "$GOT_NAME" != "$EXPECT_NAME" || "$GOT_BUILD" != "$EXPECT_BUILD" ]]; then
  echo "FAIL: Generated.xcconfig mismatch — want ${EXPECT_NAME}+${EXPECT_BUILD}, got ${GOT_NAME}+${GOT_BUILD}" >&2
  exit 1
fi

echo "Generated.xcconfig verified: $GOT_NAME+$GOT_BUILD"