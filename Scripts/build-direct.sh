#!/bin/zsh
# Build the unsandboxed Direct flavor and prove it is unsandboxed.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project MacHeadroom.xcodeproj -scheme MacHeadroom \
  -configuration Release \
  -xcconfig Configuration/Direct.xcconfig \
  -derivedDataPath build/direct build

app="build/direct/Build/Products/Release/Mac Headroom.app"
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q "app-sandbox"; then
  echo "FAIL: Direct build still carries the sandbox entitlement" >&2
  exit 1
fi
echo "OK: unsandboxed Direct build at $app"
