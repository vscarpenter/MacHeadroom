#!/bin/zsh
# Stage a free Direct download and Sparkle appcast. Upload only with --publish.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: Scripts/publish-direct.sh [--stage-only | --publish] [--output-dir PATH] path/to/release.dmg

Default: validate the notarized DMG and stage the free download, manifest,
and appcast with a signed download locally. This uses the Sparkle key in Keychain.
--publish also uploads to S3, invalidates CloudFront, and checks public delivery.
--output-dir chooses a new staging directory; it must not already exist.
By default, staging uses a fresh directory under build/direct-publish/.
A successful publication writes publish.json only after public verification.

Publishing requires DIRECT_RELEASE_BUCKET, DIRECT_SITE_BUCKET, and
DIRECT_CLOUDFRONT_DISTRIBUTION_ID. CloudFront must map /direct/updates/*
to the release bucket's updates/* and /direct/appcast.xml to the site bucket.
See Documentation/DirectEditionRunbook.md. No purchase or claim token is needed.
EOF
}
fail() { echo "FAIL: $*" >&2; exit 1; }

publish=no
output_dir=""
mode=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --publish|--stage-only|--dry-run)
      [[ -z "$mode" ]] || fail "choose only one of --stage-only or --publish"
      mode="$1"
      [[ "$1" != --publish ]] || publish=yes
      shift ;;
    --output-dir)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "--output-dir requires a path"
      [[ -z "$output_dir" ]] || fail "--output-dir may only be specified once"
      output_dir="${2:A}"
      shift 2 ;;
    --) shift; break ;;
    -*) fail "unknown option: $1" ;;
    *) break ;;
  esac
done
[[ $# == 1 ]] || { usage >&2; exit 1; }
dmg="${1:A}"
[[ -f "$dmg" ]] || fail "no DMG at $dmg"
[[ -z "$output_dir" || ( ! -e "$output_dir" && ! -L "$output_dir" ) ]] ||
  fail "output directory already exists: $output_dir"
[[ -x Vendor/Sparkle/bin/generate_appcast ]] || fail "run Scripts/fetch-sparkle.sh first"
if [[ "$publish" == yes ]]; then
  : "${DIRECT_RELEASE_BUCKET:?Set this to the S3 release bucket name.}"
  : "${DIRECT_SITE_BUCKET:?Set this to the S3 bucket serving www.macheadroom.com.}"
  : "${DIRECT_CLOUDFRONT_DISTRIBUTION_ID:?Set this to the site CloudFront distribution ID.}"
fi

scratch="$(mktemp -d)"
mounted=no
cleanup() {
  if [[ "$mounted" == yes ]]; then hdiutil detach "$scratch/mount" >/dev/null || true; fi
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir "$scratch/mount"

# Refuse development builds, sandboxed builds, and unstapled images.
codesign --verify --strict "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
hdiutil attach -nobrowse -readonly -mountpoint "$scratch/mount" "$dmg" >/dev/null
mounted=yes
app="$scratch/mount/System Headroom Direct.app"
[[ -d "$app" ]] || fail "DMG does not contain System Headroom Direct.app"
[[ -L "$scratch/mount/Applications" && "$(readlink "$scratch/mount/Applications")" == /Applications ]] ||
  fail "DMG is missing its /Applications shortcut"
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
signing="$(codesign -dv --verbose=4 "$app" 2>&1)"
[[ "$signing" == *"Authority=Developer ID Application:"* ]] || fail "app requires Developer ID signing"
[[ "$signing" == *"runtime"* ]] || fail "app requires Hardened Runtime"
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)"
[[ "$entitlements" != *"app-sandbox"* && "$entitlements" != *"get-task-allow"* ]] ||
  fail "app carries sandbox or debug entitlements"
cp "$app/Contents/Info.plist" "$scratch/Info.plist"
binary="$(plutil -extract CFBundleExecutable raw "$scratch/Info.plist")"
for arch in arm64 x86_64; do
  lipo "$app/Contents/MacOS/$binary" -verify_arch "$arch"
done
[[ -d "$app/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle is missing"
hdiutil detach "$scratch/mount" >/dev/null
mounted=no

version="$(plutil -extract CFBundleShortVersionString raw "$scratch/Info.plist")"
build="$(plutil -extract CFBundleVersion raw "$scratch/Info.plist")"
[[ "$version" =~ '^[0-9]+(\.[0-9]+){0,2}$' && "$build" =~ '^[0-9]+$' ]] ||
  fail "expected a numeric marketing version and integer build number"
artifact="System-Headroom-Direct-${version}-${build}.dmg"
alias_name="System-Headroom-Direct.dmg"
# Fresh staging prevents reuse of an appcast signed with a retired key or receipt.
if [[ -n "$output_dir" ]]; then
  mkdir -p "${output_dir:h}"
  mkdir "$output_dir"
  staging="$output_dir"
else
  mkdir -p build/direct-publish
  staging="$(mktemp -d "$PWD/build/direct-publish/${version}-${build}.XXXXXX")"
fi
mkdir "$staging/updates"
cp "$dmg" "$staging/updates/$artifact"
cp "$scratch/Info.plist" "$staging/Info.plist"

Vendor/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://www.macheadroom.com/direct/updates/" \
  -o "$staging/appcast.xml" "$staging/updates"
# Validate against the public key embedded in THIS app, not only the Keychain key.
xcrun swift Scripts/verify-direct-appcast.swift \
  "$staging/appcast.xml" "$staging/updates/$artifact" "$staging/Info.plist"
python3 Scripts/direct-release-metadata.py create \
  "$staging/Info.plist" "$staging/updates/$artifact" "$staging/updates/latest.json"
cp "$staging/updates/$artifact" "$staging/updates/$alias_name"

echo "Staged free Direct release: $staging"
echo "Landing-page link: https://www.macheadroom.com/direct/updates/$alias_name"
if [[ "$publish" != yes ]]; then
  echo "No files uploaded. Re-run with --publish to publish this DMG."
  exit 0
fi

# Never treat an unreadable manifest as permission to roll users backwards.
existing="$(aws s3api list-objects-v2 --bucket "$DIRECT_RELEASE_BUCKET" \
  --prefix updates/latest.json --query 'Contents[].Key' --output text)"
if [[ "$existing" == *"updates/latest.json"* ]]; then
  aws s3 cp "s3://$DIRECT_RELEASE_BUCKET/updates/latest.json" "$scratch/previous.json" --only-show-errors
  python3 Scripts/direct-release-metadata.py compare \
    "$scratch/previous.json" "$staging/updates/latest.json"
fi
existing_artifact="$(aws s3api list-objects-v2 --bucket "$DIRECT_RELEASE_BUCKET" \
  --prefix "updates/$artifact" --query 'Contents[].Key' --output text)"
if [[ "$existing_artifact" == *"updates/$artifact"* ]]; then
  # Retries may reuse identical bytes, but a public versioned URL is immutable.
  aws s3 cp "s3://$DIRECT_RELEASE_BUCKET/updates/$artifact" "$scratch/existing.dmg" --only-show-errors
  cmp -s "$scratch/existing.dmg" "$staging/updates/$artifact" ||
    fail "versioned DMG already exists with different bytes; increment the build number"
fi

aws s3 cp "$staging/updates/$artifact" "s3://$DIRECT_RELEASE_BUCKET/updates/$artifact" \
  --content-type application/x-apple-diskimage --cache-control 'public,max-age=31536000,immutable' --only-show-errors
# Prove public routing before advertising the release to installed apps.
curl --fail --silent --show-error --proto '=https' \
  "https://www.macheadroom.com/direct/updates/$artifact" -o "$scratch/public.dmg"
cmp -s "$scratch/public.dmg" "$staging/updates/$artifact" || fail "public DMG differs from the staged release"

aws s3 cp "$staging/updates/$alias_name" "s3://$DIRECT_RELEASE_BUCKET/updates/$alias_name" \
  --content-type application/x-apple-diskimage --cache-control 'no-cache,max-age=0,must-revalidate' --only-show-errors
aws s3 cp "$staging/updates/latest.json" "s3://$DIRECT_RELEASE_BUCKET/updates/latest.json" \
  --content-type application/json --cache-control 'no-cache,max-age=0,must-revalidate' --only-show-errors
aws s3 cp "$staging/appcast.xml" "s3://$DIRECT_SITE_BUCKET/direct/appcast.xml" \
  --content-type application/xml --cache-control 'no-cache,max-age=0,must-revalidate' --only-show-errors
invalidation="$(aws cloudfront create-invalidation \
  --distribution-id "$DIRECT_CLOUDFRONT_DISTRIBUTION_ID" \
  --paths /direct/appcast.xml "/direct/updates/$alias_name" /direct/updates/latest.json \
  --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed \
  --distribution-id "$DIRECT_CLOUDFRONT_DISTRIBUTION_ID" --id "$invalidation"
for remote in appcast.xml updates/latest.json "updates/$alias_name"; do
  curl --fail --silent --show-error --proto '=https' \
    "https://www.macheadroom.com/direct/$remote" -o "$scratch/public-file"
  cmp -s "$scratch/public-file" "$staging/$remote" || fail "public $remote differs from the staged release"
done
python3 - "$staging/updates/latest.json" "$staging/publish.json" "$invalidation" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
receipt = {
    "version": manifest["version"],
    "build": manifest["build"],
    "downloadURL": "https://www.macheadroom.com/direct/updates/System-Headroom-Direct.dmg",
    "artifactURL": manifest["downloadURL"],
    "sha256": manifest["sha256"],
    "publishedAt": datetime.now(timezone.utc).isoformat(),
    "cloudfrontInvalidationID": sys.argv[3],
}
with Path(sys.argv[2]).open("x") as stream:
    json.dump(receipt, stream, indent=2)
    stream.write("\n")
PY
echo "OK: published and verified free System Headroom Direct $version ($build)"
