#!/usr/bin/env bash
set -euo pipefail

app="$1"
sparkle_bin=".build/artifacts/sparkle/Sparkle/bin"
plist="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist")
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist")
tag="v$version"
out=".build/release-$version"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit your changes first: the release is tagged at HEAD." >&2
  exit 1
fi
if gh release view "$tag" >/dev/null 2>&1; then
  echo "$tag already exists. Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist." >&2
  exit 1
fi
latest_build=$(gh release download --pattern appcast.xml --output - 2>/dev/null | sed -n 's:.*<sparkle\:version>\(.*\)</sparkle\:version>.*:\1:p' | head -1)
if [[ -n "$latest_build" && "$build" -le "$latest_build" ]]; then
  echo "CFBundleVersion $build must be greater than the published $latest_build." >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/Flick-$version.zip"
"$sparkle_bin/generate_appcast" --account flick \
  --download-url-prefix "https://github.com/betterCallHex/flick/releases/download/$tag/" \
  -o "$out/appcast.xml" "$out"

git push origin HEAD
gh release create "$tag" "$out/Flick-$version.zip" "$out/appcast.xml" \
  --target "$(git rev-parse HEAD)" --title "Flick $version" --generate-notes
