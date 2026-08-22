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

# Sparkle's Info.plist keys. INFOPLIST_KEY_ passthrough silently drops keys
# Xcode does not know, and the shared SystemHeadroom/Info.plist must stay
# Sparkle-free for the App Store flavor, so the Direct flavor gets them here,
# before Xcode seals the bundle signature.
info_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
plutil -replace SUFeedURL -string "https://www.macheadroom.com/direct/appcast.xml" "$info_plist"
plutil -replace SUEnableAutomaticChecks -bool true "$info_plist"
plutil -replace SUPublicEDKey -string "${DIRECT_SPARKLE_PUBLIC_ED_KEY:-}" "$info_plist"

identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -n "$identity" ] && [ "$identity" != "-" ]; then
  framework="$dest/Sparkle.framework"
  for nested in \
    "$framework/Versions/B/XPCServices/Downloader.xpc" \
    "$framework/Versions/B/XPCServices/Installer.xpc" \
    "$framework/Versions/B/Autoupdate" \
    "$framework/Versions/B/Updater.app"; do
    if [ -e "$nested" ]; then
      codesign --force --options runtime --timestamp --sign "$identity" "$nested"
    fi
  done
  codesign --force --options runtime --timestamp --sign "$identity" "$framework"
fi
