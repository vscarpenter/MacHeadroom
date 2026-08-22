#!/bin/zsh
# Vendor the pinned Sparkle release (framework + signing/appcast tools).
# Sparkle ships only in the Direct flavor; the App Store binary must stay
# free of it, so the framework is fetched on demand and git-ignored.
set -euo pipefail
cd "$(dirname "$0")/.."

version="2.9.6"
sha256_expected="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
url="https://github.com/sparkle-project/Sparkle/releases/download/${version}/Sparkle-${version}.tar.xz"
dest="Vendor/Sparkle"

if [[ -f "$dest/.version" && "$(cat "$dest/.version")" == "$version" ]]; then
  echo "OK: Sparkle $version already vendored at $dest"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/sparkle.tar.xz" "$url"
sha256_actual="$(/usr/bin/shasum -a 256 "$tmp/sparkle.tar.xz" | awk '{print $1}')"
if [[ "$sha256_actual" != "$sha256_expected" ]]; then
  echo "FAIL: Sparkle checksum mismatch (expected $sha256_expected, got $sha256_actual)" >&2
  exit 1
fi

tar -xJf "$tmp/sparkle.tar.xz" -C "$tmp"
rm -rf "$dest"
mkdir -p "$dest"
ditto "$tmp/Sparkle.framework" "$dest/Sparkle.framework"
ditto "$tmp/bin" "$dest/bin"
echo "$version" > "$dest/.version"

echo "OK: vendored Sparkle $version at $dest"
