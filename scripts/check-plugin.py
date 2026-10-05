#!/usr/bin/env python3
import json
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1] / "plugin"
manifest = json.loads((root / ".codex-plugin/plugin.json").read_text())
version = plistlib.loads((root.parent / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
assert manifest["name"] == "galpium" and manifest["version"] == version
assert manifest["license"] == "Apache-2.0"
assert "Version 2.0, January 2004" in (root.parent / "LICENSE").read_text()
assert manifest["author"]["name"] and manifest["interface"]["displayName"]
config = json.loads((root / manifest["mcpServers"]).read_text())
entry = config["mcpServers"]["galpium"]
assert entry["command"] == "/bin/sh"
assert entry["args"] == ["-c", (root / "scripts/start-mcp.sh").read_text()]
skills = root / manifest["skills"]
assert (skills / "wiki/SKILL.md").read_text().startswith("---\n")
market = json.loads((root.parent / ".agents/plugins/marketplace.json").read_text())
assert market["plugins"][0]["source"]["path"] == "./plugin"
assert market["plugins"][0]["policy"]["installation"] == "AVAILABLE"
print("PASS: desktop-compatible plugin manifest, MCP launch path and wiki skill")
