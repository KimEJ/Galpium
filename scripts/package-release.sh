#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
arch=$(uname -m)
stage=$(mktemp -d "$PWD/dist/.dmg-XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp -R dist/Galpium.app "$stage/Galpium.app"
ln -s /Applications "$stage/Applications"
dmg="dist/Galpium-$version-$arch.dmg"
hdiutil create -ov -volname "Galpium $version" -srcfolder "$stage" -format UDZO "$dmg"
sh scripts/package-plugin.sh
(cd dist && shasum -a 256 "$(basename "$dmg")" "Galpium-Codex-Plugin-$version.zip") > dist/SHA256SUMS
printf 'Packaged %s\n' "$dmg"
