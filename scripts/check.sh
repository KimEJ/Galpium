#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/galpium-clang-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/private/tmp/galpium-module-cache}"
swift format lint --strict --recursive Sources Tests Package.swift
swift test --disable-sandbox --cache-path /private/tmp/galpium-swift-cache
bin=$(swift build --show-bin-path --disable-sandbox --cache-path /private/tmp/galpium-swift-cache)
python3 scripts/test_mcp.py --binary "$bin/galpium-mcp"
python3 scripts/test_resilience.py --binary "$bin/galpium-mcp"
python3 -m py_compile scripts/test_mcp.py
plutil -lint Resources/Info.plist
python3 scripts/check-localizations.py
python3 scripts/check-plugin.py
