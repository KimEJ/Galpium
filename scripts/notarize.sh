#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${GALPIUM_SIGN_IDENTITY:?Set the publisher Developer ID identity}"
: "${GALPIUM_NOTARY_PROFILE:?Set the existing notarytool keychain profile name}"
sh scripts/package-release.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
dmg="dist/Galpium-$version-$(uname -m).dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$GALPIUM_NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
(cd dist && shasum -a 256 "$(basename "$dmg")" "Galpium-Codex-Plugin-$version.zip") > dist/SHA256SUMS
