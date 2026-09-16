#!/bin/zsh
# Build the universal, unsandboxed Direct flavor for local testing.
set -euo pipefail
cd "$(dirname "$0")/.."

signing_settings=()
case "${1:-}" in
  --help|-h)
    cat <<'HELP'
Usage: Scripts/build-direct.sh [--ad-hoc]

Build and verify the Direct edition for Apple silicon and Intel Macs.
The default uses the project's development signing configuration.
--ad-hoc requires no signing certificate and disables the hardened runtime
for CI/local tests, allowing Sparkle's vendor-signed framework to load.
Customer downloads must use Scripts/release-direct.sh instead.

If xcode-select points to Command Line Tools, set:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
HELP
    exit 0
    ;;
  --ad-hoc)
    signing_settings=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO)
    shift
    ;;
  "") ;;
  *) echo "FAIL: unknown option: $1 (see --help)" >&2; exit 1 ;;
esac
[[ $# -eq 0 ]] || { echo "FAIL: unexpected argument: $1 (see --help)" >&2; exit 1; }

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "FAIL: select a full Xcode installation, or set DEVELOPER_DIR (see --help)" >&2
  exit 1
fi
[[ -d Vendor/Sparkle/Sparkle.framework ]] || {
  echo "FAIL: Sparkle is missing; run Scripts/fetch-sparkle.sh first" >&2
  exit 1
}

xcodebuild -project SystemHeadroom.xcodeproj -scheme SystemHeadroom \
  -configuration Release \
  -xcconfig Configuration/Direct.xcconfig \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/direct \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  "${signing_settings[@]}" build

app="build/direct/Build/Products/Release/System Headroom Direct.app"
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)" || {
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
executable="$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist")"
for architecture in arm64 x86_64; do
  lipo "$app/Contents/MacOS/$executable" -verify_arch "$architecture" || {
    echo "FAIL: Direct build is missing the $architecture architecture" >&2
    exit 1
  }
done

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

echo "OK: universal, unsandboxed Direct build $actual_version ($actual_build) at $app"
