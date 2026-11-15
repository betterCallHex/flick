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
latest_build=$(gh release download --pattern appcast.xml --output - 2>/dev/null | sed -n 's:.*<sparkle\:version>\(.*\)</sparkle\:version>.*:\1:p' | head -1 || true)
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
uvx dmgbuild -s scripts/dmg-settings.py -D app="$app" Flick "$out/Flick-$version.dmg"

git push origin HEAD
gh release create "$tag" "$out/Flick-$version.dmg" "$out/Flick-$version.zip" "$out/appcast.xml" \
  --target "$(git rev-parse HEAD)" --title "Flick $version" --generate-notes

tap="$out/homebrew-tap"
gh repo clone betterCallHex/homebrew-tap "$tap" -- --depth 1 --quiet
sed -i '' -E \
  -e "s/^  version \".*\"/  version \"$version\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$(shasum -a 256 "$out/Flick-$version.dmg" | cut -d' ' -f1)\"/" \
  "$tap/Casks/flick.rb"
git -C "$tap" commit -qam "flick $version"
git -C "$tap" push -q
