#!/bin/sh
set -eu
package_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ ! -d "$package_root/plugin" ]; then
  package_root=$(dirname "$package_root")
fi

# Use the runtime shipped with the desktop app; no separate CLI install is needed.
desktop_codex=/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex
if [ ! -x "$desktop_codex" ]; then
  desktop_codex="$HOME/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
fi
if [ ! -x "$desktop_codex" ]; then
  printf 'Install ChatGPT in Applications before installing this plugin.\n' >&2
  exit 1
fi
if [ ! -x /Applications/Galpium.app/Contents/MacOS/galpium-mcp ] &&
   [ ! -x "$HOME/Applications/Galpium.app/Contents/MacOS/galpium-mcp" ]; then
  printf 'Install Galpium.app in Applications before installing this plugin.\n' >&2
  exit 1
fi

marketplace_root="$HOME/.codex/plugins/local/galpium-marketplace"
mkdir -p "$marketplace_root/.agents/plugins"
ditto "$package_root/plugin" "$marketplace_root/plugin"
cp "$package_root/.agents/plugins/marketplace.json" "$marketplace_root/.agents/plugins/marketplace.json"
"$desktop_codex" plugin marketplace add "$marketplace_root"
"$desktop_codex" plugin add galpium@galpium-local
printf 'Galpium installed. Restart ChatGPT, then start a new local chat and select @Galpium.\n'
