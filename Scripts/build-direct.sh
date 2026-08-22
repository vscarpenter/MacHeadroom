#!/bin/zsh
# Build the unsandboxed Direct flavor and prove it is unsandboxed.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project SystemHeadroom.xcodeproj -scheme SystemHeadroom \
  -configuration Release \
  -xcconfig Configuration/Direct.xcconfig \
  -derivedDataPath build/direct build

app="build/direct/Build/Products/Release/System Headroom Direct.app"
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
  xcodebuild -project SystemHeadroom.xcodeproj -scheme SystemHeadroom \
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
actual_bundle_id="$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")"
if [[ "$actual_version" != "$expected_version" || "$actual_build" != "$expected_build" ]]; then
  echo "FAIL: Direct version $actual_version ($actual_build) does not match Release $expected_version ($expected_build)" >&2
  exit 1
fi
if [[ "$actual_bundle_id" != "com.vinnycarpenter.SystemHeadroom.Direct" ]]; then
  echo "FAIL: Direct build has unexpected bundle identifier $actual_bundle_id" >&2
  exit 1
fi

# Sparkle must be embedded here and only here; the App Store flavor's
# absence is pinned by UpdaterGatingTests in the normal suite.
if [[ ! -d "$app/Contents/Frameworks/Sparkle.framework" ]]; then
  echo "FAIL: Direct build is missing Sparkle.framework (run Scripts/fetch-sparkle.sh)" >&2
  exit 1
fi
feed_url="$(plutil -extract SUFeedURL raw "$app/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$feed_url" != "https://www.macheadroom.com/direct/appcast.xml" ]]; then
  echo "FAIL: Direct build SUFeedURL is '$feed_url'" >&2
  exit 1
fi
public_key="$(plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$public_key" ]]; then
  echo "WARN: SUPublicEDKey is empty; dev builds tolerate this, release-direct.sh does not"
fi

echo "OK: unsandboxed Direct build $actual_version ($actual_build) at $app"
