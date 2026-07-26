#!/bin/zsh
# Build the unsandboxed Direct flavor and prove it is unsandboxed.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project MacHeadroom.xcodeproj -scheme MacHeadroom \
  -configuration Release \
  -xcconfig Configuration/Direct.xcconfig \
  -derivedDataPath build/direct build

app="build/direct/Build/Products/Release/Mac Headroom.app"
entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null)" || {
  echo "FAIL: codesign could not read entitlements from $app" >&2
  exit 1
}
if grep -q "app-sandbox" <<<"$entitlements"; then
  echo "FAIL: Direct build still carries the sandbox entitlement" >&2
  exit 1
fi
echo "OK: unsandboxed Direct build at $app"
