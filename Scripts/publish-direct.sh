#!/bin/zsh
# Publish a notarized Direct DMG: stage it under its versioned name, sign the
# update for Sparkle, regenerate the appcast, and upload — DMG and manifest to
# the private release bucket (served only via presigned handoff URLs and the
# CDN updates path), appcast to the site. Uploads are confirmed interactively.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DIRECT_RELEASE_BUCKET:?Set this to the private S3 release bucket name.}"
: "${DIRECT_SITE_BUCKET:?Set this to the S3 bucket serving www.macheadroom.com.}"
: "${DIRECT_CLOUDFRONT_DISTRIBUTION_ID:?Set this to the macheadroom.com CloudFront distribution ID.}"

dmg="${1:?Usage: publish-direct.sh path/to/System Headroom Direct.dmg}"
[[ -f "$dmg" ]] || { echo "FAIL: no DMG at $dmg" >&2; exit 1; }
[[ -x Vendor/Sparkle/bin/generate_appcast ]] || {
  echo "FAIL: Sparkle tools missing. Run Scripts/fetch-sparkle.sh first." >&2
  exit 1
}

# Read identity from the app inside the DMG; refuse unkeyed builds.
mount_point="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$dmg" >/dev/null
info="$mount_point/System Headroom Direct.app/Contents/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$info")"
build="$(plutil -extract CFBundleVersion raw "$info")"
public_key="$(plutil -extract SUPublicEDKey raw "$info" 2>/dev/null || true)"
hdiutil detach "$mount_point" >/dev/null
if [[ -z "$public_key" ]]; then
  echo "FAIL: the DMG's app has no SUPublicEDKey; it cannot update itself" >&2
  exit 1
fi

artifact="System-Headroom-Direct-${version}.dmg"
staging="build/direct-publish/${version}-${build}"
mkdir -p "$staging/updates"
cp "$dmg" "$staging/updates/$artifact"
sha256="$(/usr/bin/shasum -a 256 "$staging/updates/$artifact" | awk '{print $1}')"

# generate_appcast signs with the EdDSA key in the login Keychain and reads
# version metadata out of the archive itself.
Vendor/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://www.macheadroom.com/direct/updates/" \
  -o "$staging/appcast.xml" "$staging/updates"

cat > "$staging/updates/latest.json" <<JSON
{"version":"$version","build":"$build","key":"updates/$artifact","sha256":"$sha256","releasedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON

echo "Staged $artifact ($version ($build), sha256 $sha256)"
echo "About to upload:"
echo "  s3://$DIRECT_RELEASE_BUCKET/updates/$artifact"
echo "  s3://$DIRECT_RELEASE_BUCKET/updates/latest.json"
echo "  s3://$DIRECT_SITE_BUCKET/direct/appcast.xml (+ CloudFront invalidation)"
read -q "REPLY?Proceed? (y/n) "
echo
[[ "$REPLY" == "y" ]] || { echo "Aborted; staged files remain in $staging"; exit 1; }

aws s3 cp "$staging/updates/$artifact" "s3://$DIRECT_RELEASE_BUCKET/updates/$artifact"
aws s3 cp "$staging/updates/latest.json" "s3://$DIRECT_RELEASE_BUCKET/updates/latest.json" \
  --content-type application/json
aws s3 cp "$staging/appcast.xml" "s3://$DIRECT_SITE_BUCKET/direct/appcast.xml" \
  --content-type application/xml
aws cloudfront create-invalidation \
  --distribution-id "$DIRECT_CLOUDFRONT_DISTRIBUTION_ID" \
  --paths "/direct/appcast.xml" >/dev/null

echo "OK: published System Headroom Direct $version ($build)"
