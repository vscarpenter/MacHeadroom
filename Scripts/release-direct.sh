#!/bin/zsh
# Produce a customer-downloadable Direct edition. Developer ID signing and
# accepted notarization are required; this script never publishes anything.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*" >&2; exit 1; }
usage() {
  cat <<'HELP'
Usage: Scripts/release-direct.sh [--preflight] [--output-dir PATH]

Archive a universal (Apple silicon + Intel), unsandboxed Direct edition,
notarize and staple the app, then create a signed, notarized DMG with an
Applications shortcut. Sparkle remains enabled for Direct updates.

Required environment variables:
  DIRECT_DEVELOPER_ID_APPLICATION  Full Developer ID Application identity
  DIRECT_DEVELOPER_TEAM_ID         Apple Developer Team ID
  DIRECT_NOTARY_PROFILE           Existing notarytool Keychain profile name

Options:
  --preflight        Check local prerequisites without building, signing,
                     contacting Apple, or uploading anything. Notary profile
                     credentials are verified by Apple only during a release.
  --output-dir PATH  New output directory (must not already exist)
  --help            Show this help

Outputs (under build/direct-release/<timestamp>-<unique>/ by default):
  System-Headroom-Direct-<version>-<build>.dmg
  release.json, SHA256SUMS, archive, and notarization receipts

If xcode-select points to Command Line Tools, set:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

Publish separately with Scripts/publish-direct.sh after inspecting the DMG.
HELP
}

preflight_only=false
requested_output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preflight) preflight_only=true; shift ;;
    --output-dir)
      [[ $# -ge 2 && -n "$2" ]] || fail "--output-dir requires a path"
      requested_output="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) fail "unknown option: $1 (see --help)" ;;
  esac
done

# Report all missing prerequisites together. Never generate signing keys or
# read their private material; only list available code-signing identities.
preflight_failed=false
missing() { echo "FAIL: $*" >&2; preflight_failed=true; }
for tool in xcodebuild xcrun codesign security plutil lipo hdiutil ditto python3 shasum spctl; do
  command -v "$tool" >/dev/null 2>&1 || missing "required command not found: $tool"
done
if ! xcodebuild -version >/dev/null 2>&1; then
  missing "select a full Xcode installation, or set DEVELOPER_DIR (see --help)"
fi
xcrun --find notarytool >/dev/null 2>&1 || missing "notarytool is unavailable in the selected Xcode"
xcrun --find stapler >/dev/null 2>&1 || missing "stapler is unavailable in the selected Xcode"
[[ -d Vendor/Sparkle/Sparkle.framework ]] || missing "Sparkle is missing; run Scripts/fetch-sparkle.sh first"
[[ -n "${DIRECT_DEVELOPER_ID_APPLICATION:-}" ]] || missing "set DIRECT_DEVELOPER_ID_APPLICATION to your Developer ID Application identity"
[[ -n "${DIRECT_DEVELOPER_TEAM_ID:-}" ]] || missing "set DIRECT_DEVELOPER_TEAM_ID to your Apple Developer Team ID"
[[ -n "${DIRECT_NOTARY_PROFILE:-}" ]] || missing "set DIRECT_NOTARY_PROFILE to an existing notarytool Keychain profile name"
if [[ -n "$requested_output" && -e "$requested_output" ]]; then
  missing "output directory already exists: $requested_output (choose a new path)"
fi
if [[ -n "${DIRECT_DEVELOPER_ID_APPLICATION:-}" && -n "${DIRECT_DEVELOPER_TEAM_ID:-}" ]]; then
  if [[ "$DIRECT_DEVELOPER_ID_APPLICATION" != "Developer ID Application: "*" ($DIRECT_DEVELOPER_TEAM_ID)" ]]; then
    missing "DIRECT_DEVELOPER_ID_APPLICATION must be a Developer ID Application certificate for team $DIRECT_DEVELOPER_TEAM_ID"
  elif ! security find-identity -v -p codesigning | \
    awk -v identity="$DIRECT_DEVELOPER_ID_APPLICATION" -F '"' '$2 == identity { found = 1 } END { exit !found }'; then
    missing "the requested Developer ID Application identity is not available in the current Keychain"
  fi
fi
[[ "$preflight_failed" == false ]] || exit 1

# The overlay must inherit the App Store release's version. Read both before
# archiving so a configuration error does not consume a notarization upload.
release_settings="$(xcodebuild -project SystemHeadroom.xcodeproj -scheme SystemHeadroom \
  -configuration Release -showBuildSettings 2>/dev/null)"
direct_settings="$(xcodebuild -project SystemHeadroom.xcodeproj -scheme SystemHeadroom \
  -configuration Release -xcconfig Configuration/Direct.xcconfig -showBuildSettings 2>/dev/null)"
setting() { awk -v key="$1" -F ' = ' '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'; }
expected_version="$(setting MARKETING_VERSION <<<"$release_settings")"
expected_build="$(setting CURRENT_PROJECT_VERSION <<<"$release_settings")"
[[ "$(setting MARKETING_VERSION <<<"$direct_settings")" == "$expected_version" ]] || fail "Direct MARKETING_VERSION differs from Release"
[[ "$(setting CURRENT_PROJECT_VERSION <<<"$direct_settings")" == "$expected_build" ]] || fail "Direct CURRENT_PROJECT_VERSION differs from Release"
public_key="$(setting DIRECT_SPARKLE_PUBLIC_ED_KEY <<<"$direct_settings")"
python3 - "$expected_version" "$expected_build" "$public_key" <<'PY'
import base64
import re
import sys

version, build, key = sys.argv[1:]
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
    sys.exit(f"FAIL: MARKETING_VERSION must contain 1-3 numeric components: {version!r}")
if not re.fullmatch(r"[0-9]+", build):
    sys.exit(f"FAIL: CURRENT_PROJECT_VERSION must be an integer build number: {build!r}")
try:
    valid_key = len(base64.b64decode(key, validate=True)) == 32
except ValueError:
    valid_key = False
if not valid_key:
    sys.exit("FAIL: DIRECT_SPARKLE_PUBLIC_ED_KEY must be a valid 32-byte Ed25519 public key")
PY

echo "OK: local release prerequisites for Direct $expected_version ($expected_build)"
echo "Notary profile: $DIRECT_NOTARY_PROFILE (Apple authenticates it during submission)"
[[ "$preflight_only" == false ]] || exit 0

if [[ -n "$requested_output" ]]; then
  mkdir -p "$(dirname "$requested_output")"
  mkdir "$requested_output"
  release_root="${requested_output:A}"
else
  mkdir -p build/direct-release
  release_root="$(mktemp -d "${PWD}/build/direct-release/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
fi
archive_path="$release_root/System Headroom Direct.xcarchive"
dmg_staging=""
cleanup() {
  if [[ -n "$dmg_staging" && -d "$dmg_staging" ]]; then
    rm -rf "$dmg_staging"
  fi
}
trap cleanup EXIT

xcodebuild archive \
  -project SystemHeadroom.xcodeproj \
  -scheme SystemHeadroom \
  -configuration Release \
  -xcconfig Configuration/Direct.xcconfig \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DIRECT_DEVELOPER_ID_APPLICATION" \
  DEVELOPMENT_TEAM="$DIRECT_DEVELOPER_TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS=--timestamp

app="$archive_path/Products/Applications/System Headroom Direct.app"
[[ -d "$app" ]] || fail "archive did not produce the Direct app"
info="$app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app"
# Recent codesign versions default to a human-readable [Dict] representation.
# Request XML explicitly because the safety checks parse this as a plist.
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)"
printf '%s' "$entitlements" | python3 -c '
import plistlib, sys
raw = sys.stdin.buffer.read()
entitlements = plistlib.loads(raw) if raw.strip() else {}
if "com.apple.security.app-sandbox" in entitlements:
    sys.exit("FAIL: Direct archive still carries the sandbox entitlement")
if entitlements.get("com.apple.security.get-task-allow"):
    sys.exit("FAIL: Direct archive has the debugger entitlement enabled")
'
signature="$(codesign -d --verbose=4 "$app" 2>&1)"
[[ "$signature" == *"Authority=$DIRECT_DEVELOPER_ID_APPLICATION"* ]] || fail "archive is not signed with the requested Developer ID identity"
[[ "$signature" == *"TeamIdentifier=$DIRECT_DEVELOPER_TEAM_ID"* ]] || fail "archive is signed by an unexpected team"
[[ "$signature" == *"(runtime)"* ]] || fail "archive is missing the hardened runtime"
[[ "$signature" == *"Timestamp="* ]] || fail "archive signature has no secure timestamp"

version="$(plutil -extract CFBundleShortVersionString raw "$info")"
build="$(plutil -extract CFBundleVersion raw "$info")"
[[ "$version" == "$expected_version" && "$build" == "$expected_build" ]] || fail "Direct archive version $version ($build) does not match Release $expected_version ($expected_build)"
bundle_id="$(plutil -extract CFBundleIdentifier raw "$info")"
[[ "$bundle_id" == com.vinnycarpenter.SystemHeadroom.Direct ]] || fail "Direct archive has unexpected bundle identifier $bundle_id"
executable="$(plutil -extract CFBundleExecutable raw "$info")"
for architecture in arm64 x86_64; do
  lipo "$app/Contents/MacOS/$executable" -verify_arch "$architecture" || fail "Direct executable is missing $architecture"
done

[[ -d "$app/Contents/Frameworks/Sparkle.framework" ]] || fail "Direct archive is missing Sparkle.framework"
codesign --verify --deep --strict "$app/Contents/Frameworks/Sparkle.framework"
for architecture in arm64 x86_64; do
  lipo "$app/Contents/Frameworks/Sparkle.framework/Sparkle" -verify_arch "$architecture" || fail "Sparkle is missing $architecture"
done
feed_url="$(plutil -extract SUFeedURL raw "$info" 2>/dev/null || true)"
[[ "$feed_url" == https://www.macheadroom.com/direct/appcast.xml ]] || fail "Direct archive SUFeedURL is '$feed_url'"
[[ "$(plutil -extract SUPublicEDKey raw "$info" 2>/dev/null || true)" == "$public_key" ]] || fail "Direct archive has a missing or unexpected Sparkle public key"

# notarytool may successfully deliver a rejected submission. Inspect the JSON
# status explicitly and retain each receipt for review before any stapling.
notarize() {
  local submitted_file="$1" receipt="$2"
  xcrun notarytool submit "$submitted_file" \
    --keychain-profile "$DIRECT_NOTARY_PROFILE" --wait --output-format json > "$receipt"
  python3 - "$receipt" <<'PY'
import json
import sys
from pathlib import Path

receipt = Path(sys.argv[1])
try:
    result = json.loads(receipt.read_text())
except (OSError, ValueError) as error:
    sys.exit(f"FAIL: could not read notarization receipt {receipt}: {error}")
if result.get("status") != "Accepted":
    sys.exit(f"FAIL: notarization status is {result.get('status')!r}; submission {result.get('id', 'unknown')}. Inspect {receipt} and retrieve the notarytool log before retrying.")
print(f"OK: notarization accepted ({result.get('id', 'unknown')})")
PY
}

artifact="System-Headroom-Direct-${version}-${build}"
app_zip="$release_root/$artifact.zip"
ditto -c -k --keepParent "$app" "$app_zip"
notarize "$app_zip" "$release_root/notarization-app.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"

dmg_staging="$(mktemp -d "$release_root/.dmg-staging-XXXXXX")"
ditto "$app" "$dmg_staging/System Headroom Direct.app"
ln -s /Applications "$dmg_staging/Applications"
dmg="$release_root/$artifact.dmg"
hdiutil create -volname "System Headroom Direct" -srcfolder "$dmg_staging" \
  -fs HFS+ -format UDZO "$dmg"
codesign --sign "$DIRECT_DEVELOPER_ID_APPLICATION" --timestamp "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
notarize "$dmg" "$release_root/notarization-dmg.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"

python3 - "$info" "$dmg" "$release_root/release.json" <<'PY'
import datetime
import hashlib
import json
import plistlib
import subprocess
import sys
from pathlib import Path

info_path, dmg_path, metadata_path = map(Path, sys.argv[1:])
with info_path.open("rb") as stream:
    info = plistlib.load(stream)
digest = hashlib.sha256()
with dmg_path.open("rb") as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
revision = subprocess.run(["git", "rev-parse", "HEAD"], text=True, capture_output=True)
worktree = subprocess.run(["git", "status", "--porcelain"], text=True, capture_output=True)
metadata = {
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "bundle_id": info["CFBundleIdentifier"],
    "minimum_system_version": info["LSMinimumSystemVersion"],
    "architectures": ["arm64", "x86_64"],
    "dmg": dmg_path.name,
    "sha256": digest.hexdigest(),
    "size": dmg_path.stat().st_size,
    "git_commit": revision.stdout.strip() if revision.returncode == 0 else None,
    "git_dirty": bool(worktree.stdout.strip()) if worktree.returncode == 0 else None,
    "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
}
metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")
(metadata_path.parent / "SHA256SUMS").write_text(f"{metadata['sha256']}  {dmg_path.name}\n")
PY

echo "OK: notarized universal Direct download at $dmg"
echo "Release metadata: $release_root/release.json"
echo "Next: inspect the DMG, then run Scripts/publish-direct.sh with this DMG path."
