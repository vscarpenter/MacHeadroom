#!/bin/zsh
# Build the unsandboxed Direct flavor and prove it is unsandboxed.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project MacHeadroom.xcodeproj -scheme MacHeadroom \
  -configuration Release \
  -xcconfig Configuration/Direct.xcconfig \
  -derivedDataPath build/direct build

app="build/direct/Build/Products/Release/Headroom Monitor.app"
entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null)" || {
  echo "FAIL: codesign could not read entitlements from $app" >&2
  exit 1
}
if grep -q "app-sandbox" <<<"$entitlements"; then
  echo "FAIL: Direct build still carries the sandbox entitlement" >&2
  exit 1
fi

# A command-line xcconfig has higher precedence than project settings.
# Guard against an overlay accidentally packaging Shared.xcconfig's
# fallback version instead of the current Release version.
release_settings="$(
  xcodebuild -project MacHeadroom.xcodeproj -scheme MacHeadroom \
    -configuration Release -showBuildSettings 2>/dev/null
)"
expected_version="$(
  awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / { print $2; exit }' \
    <<<"$release_settings"
)"
expected_build="$(
  awk -F ' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION = / { print $2; exit }' \
    <<<"$release_settings"
)"
actual_version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
actual_build="$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")"
if [[ "$actual_version" != "$expected_version" || "$actual_build" != "$expected_build" ]]; then
  echo "FAIL: Direct version $actual_version ($actual_build) does not match Release $expected_version ($expected_build)" >&2
  exit 1
fi

echo "OK: unsandboxed Direct build $actual_version ($actual_build) at $app"
