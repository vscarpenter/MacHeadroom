#!/bin/sh
# Xcode build phase: embed and sign Sparkle, but only for the Direct flavor
# (Direct.xcconfig sets DIRECT_EDITION_BUILD=YES). Every other configuration
# must produce a bundle with no trace of Sparkle; a test pins that.
#
# Xcode signs only frameworks it embeds itself, so this script signs what it
# copies: Sparkle's nested XPC services and helpers first, then the
# framework. --timestamp keeps Developer ID archives notarizable.
set -eu

if [ "${DIRECT_EDITION_BUILD:-NO}" != "YES" ]; then
  exit 0
fi

src="${SRCROOT}/Vendor/Sparkle/Sparkle.framework"
if [ ! -d "$src" ]; then
  echo "error: Sparkle is not vendored. Run Scripts/fetch-sparkle.sh first." >&2
  exit 1
fi

dest="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "$dest"
rm -rf "$dest/Sparkle.framework"
ditto "$src" "$dest/Sparkle.framework"
# Sparkle's Info.plist keys come from SystemHeadroom/InfoDirect.plist via
# Direct.xcconfig's INFOPLIST_FILE override — never from this script: a
# script cannot safely mutate a file the build system regenerates on its
# own schedule.

identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
# /usr/bin/codesign, not a PATH lookup: Xcode's script environment can
# otherwise pick up a different signer. A timestamp request to Apple
# sometimes fails on the second nested bundle ("A timestamp was expected
# but was not found") and succeeds on an immediate retry.
sign_timestamped() {
  target="$1"
  attempt=1
  while [ "$attempt" -le 3 ]; do
    if /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$target"; then
      return 0
    fi
    echo "warning: timestamped codesign failed for $target (attempt $attempt)" >&2
    attempt=$((attempt + 1))
    sleep 1
  done
  echo "error: timestamped codesign failed for $target" >&2
  return 1
}

if [ -n "$identity" ] && [ "$identity" != "-" ]; then
  framework="$dest/Sparkle.framework"
  for nested in \
    "$framework/Versions/B/XPCServices/Downloader.xpc" \
    "$framework/Versions/B/XPCServices/Installer.xpc" \
    "$framework/Versions/B/Autoupdate" \
    "$framework/Versions/B/Updater.app"; do
    if [ -e "$nested" ]; then
      if [ -d "$nested/Contents/MacOS" ]; then
        for executable in "$nested/Contents/MacOS"/*; do
          if [ -f "$executable" ]; then
            sign_timestamped "$executable"
          fi
        done
      fi
      sign_timestamped "$nested"
    fi
  done
  sign_timestamped "$framework"
fi
