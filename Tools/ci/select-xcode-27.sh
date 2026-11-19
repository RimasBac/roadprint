#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

installed=()
for app in /Applications/Xcode_27*.app; do
  if [[ -d "$app" && "$app" =~ /Xcode_27(\.[0-9]+)*\.app$ ]]; then
    installed+=("$app")
  fi
done

if [[ ${#installed[@]} -eq 0 ]]; then
  echo '::error::No Xcode 27.x installation found in /Applications. Use a runner with Xcode 27 and the iOS 27 SDK.' >&2
  exit 1
fi

selected=$(printf '%s\n' "${installed[@]}" | sort -V | tail -n 1)
echo "Using $selected"
sudo xcode-select --switch "$selected"
xcodebuild -version

sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
echo "iOS SDK $sdk_version"
if [[ "$sdk_version" != 27.* ]]; then
  echo "::error::Expected the iOS 27 SDK, found $sdk_version." >&2
  exit 1
fi
