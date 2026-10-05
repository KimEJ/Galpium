#!/bin/sh
set -eu
if [ -n "${GALPIUM_APP:-}" ]; then
  executable="$GALPIUM_APP/Contents/MacOS/galpium-mcp"
elif [ -x /Applications/Galpium.app/Contents/MacOS/galpium-mcp ]; then
  executable=/Applications/Galpium.app/Contents/MacOS/galpium-mcp
elif [ -x "$HOME/Applications/Galpium.app/Contents/MacOS/galpium-mcp" ]; then
  executable="$HOME/Applications/Galpium.app/Contents/MacOS/galpium-mcp"
else
  printf 'Galpium.app을 Applications에 설치하거나 GALPIUM_APP으로 앱 경로를 지정하세요.\n' >&2
  exit 1
fi
if [ -n "${GALPIUM_LIBRARY:-}" ]; then
  exec "$executable" --library "$GALPIUM_LIBRARY"
fi
exec "$executable"
