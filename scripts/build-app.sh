#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/galpium-clang-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/private/tmp/galpium-module-cache}"
python3 scripts/prepare-embedding.py
swift build -c release --disable-sandbox --cache-path /private/tmp/galpium-swift-cache
bin=$(swift build -c release --show-bin-path --disable-sandbox --cache-path /private/tmp/galpium-swift-cache)
mkdir -p dist
if [ ! -f Resources/AppIcon.icns ]; then
  swift scripts/make-icon.swift dist/AppIcon.iconset
  iconutil -c icns dist/AppIcon.iconset -o Resources/AppIcon.icns
fi
staging=$(mktemp -d "$PWD/dist/.app-XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Galpium.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Galpium" "$bin/galpium-mcp" "$bin/galpium-embedder" "$app/Contents/MacOS/"
cp -R .build/vendor/Embedding "$app/Contents/Resources/Embedding"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R "$bin/Galpium_GalpiumCore.bundle" "$app/Contents/Resources/"
cp -R Resources/*.lproj "$app/Contents/Resources/"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
cp README*.md "$app/Contents/Resources/"
cp LICENSE NOTICE THIRD-PARTY-NOTICES.md DESIGN.md "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/docs"
cp docs/*.md "$app/Contents/Resources/docs/"
if [ -n "${GALPIUM_SIGN_IDENTITY:-}" ]; then
  find "$app/Contents/Resources/Embedding/runtime" -type f -name '*.dylib' -exec codesign --force --options runtime --timestamp --sign "$GALPIUM_SIGN_IDENTITY" {} \;
  codesign --force --options runtime --timestamp --sign "$GALPIUM_SIGN_IDENTITY" "$app/Contents/Resources/Embedding/runtime/llama-server"
  codesign --force --options runtime --timestamp --sign "$GALPIUM_SIGN_IDENTITY" "$app/Contents/MacOS/galpium-embedder"
  codesign --force --options runtime --timestamp --sign "$GALPIUM_SIGN_IDENTITY" "$app/Contents/MacOS/galpium-mcp"
  codesign --force --options runtime --timestamp --sign "$GALPIUM_SIGN_IDENTITY" "$app"
else
  find "$app/Contents/Resources/Embedding/runtime" -type f -name '*.dylib' -exec codesign --force --sign - {} \;
  codesign --force --sign - "$app/Contents/Resources/Embedding/runtime/llama-server"
  codesign --force --sign - "$app/Contents/MacOS/galpium-embedder"
  codesign --force --sign - "$app/Contents/MacOS/galpium-mcp"
  codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
rm -rf dist/Galpium.app
mv "$app" dist/Galpium.app
printf 'Built %s/dist/Galpium.app\n' "$PWD"
