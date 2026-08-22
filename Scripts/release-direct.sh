#!/bin/zsh
# Produce a customer-downloadable Direct edition. This intentionally refuses
# development signing: Developer ID plus notarization are required.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DIRECT_DEVELOPER_ID_APPLICATION:?Set this to your Developer ID Application certificate name.}"
: "${DIRECT_DEVELOPER_TEAM_ID:?Set this to your Apple Developer Team ID.}"
: "${DIRECT_NOTARY_PROFILE:?Set this to a notarytool keychain profile name.}"

release_root="build/direct-release/$(date -u +%Y%m%dT%H%M%SZ)"
archive_path="$release_root/System Headroom Direct.xcarchive"
mkdir -p "$release_root"

xcodebuild archive \
  -project SystemHeadroom.xcodeproj \
  -scheme SystemHeadroom \
  -configuration Release \
  -xcconfig Configuration/Direct.xcconfig \
  -archivePath "$archive_path" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DIRECT_DEVELOPER_ID_APPLICATION" \
  DEVELOPMENT_TEAM="$DIRECT_DEVELOPER_TEAM_ID"

app="$archive_path/Products/Applications/System Headroom Direct.app"
[[ -d "$app" ]] || { echo "FAIL: archive did not produce the Direct app" >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$app"
entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null)"
if grep -q "app-sandbox" <<<"$entitlements"; then
  echo "FAIL: Direct archive still carries the sandbox entitlement" >&2
  exit 1
fi

bundle_id="$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")"
if [[ "$bundle_id" != "com.vinnycarpenter.SystemHeadroom.Direct" ]]; then
  echo "FAIL: Direct archive has unexpected bundle identifier $bundle_id" >&2
  exit 1
fi

# Notarize and staple the app itself so an extracted app remains verifiable,
# then notarize the DMG customers actually download.
app_zip="$release_root/System Headroom Direct.zip"
ditto -c -k --keepParent "$app" "$app_zip"
xcrun notarytool submit "$app_zip" --keychain-profile "$DIRECT_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"

dmg="$release_root/System Headroom Direct.dmg"
hdiutil create -volname "System Headroom Direct" -srcfolder "$app" -format UDZO -ov "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$DIRECT_NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type execute --verbose=4 "$app"
spctl --assess --type open --verbose=4 "$dmg"

echo "OK: notarized Direct download at $dmg"
