#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 scripts/check-plugin.py
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/.plugin-XXXXXX")
trap 'rm -rf "$stage"' EXIT
pluginstage="$stage/Galpium-Codex"
mkdir -p "$pluginstage/.agents/plugins"
cp -R plugin "$pluginstage/plugin"
cp .agents/plugins/marketplace.json "$pluginstage/.agents/plugins/marketplace.json"
cp scripts/install-plugin.command "$pluginstage/Install Galpium Plugin.command"
chmod +x "$pluginstage/Install Galpium Plugin.command"
cp LICENSE NOTICE "$pluginstage/"
ditto -c -k --sequesterRsrc --keepParent "$pluginstage" "dist/Galpium-Codex-Plugin-$version.zip"
printf 'Created Galpium-Codex-Plugin-%s.zip\n' "$version"
