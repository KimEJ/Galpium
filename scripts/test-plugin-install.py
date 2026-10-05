#!/usr/bin/env python3
"""Verify the shipped archive with ChatGPT desktop's own plugin loader."""
import json
import os
from pathlib import Path
import plistlib
import selectors
import stat
import subprocess
import tempfile
import time
import zipfile

project = Path(__file__).resolve().parents[1]
version = plistlib.loads((project / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
desktop = next((p for p in [Path("/Applications/ChatGPT.app"), Path.home() / "Applications/ChatGPT.app"] if p.is_dir()), None)
assert desktop, "ChatGPT desktop is required for this targeted integration check"
runtime = desktop / "Contents/Resources/codex-cli/bin/codex"

with tempfile.TemporaryDirectory(prefix="galpium-plugin-", dir="/private/tmp") as temporary:
    root = Path(temporary)
    with zipfile.ZipFile(project / f"dist/Galpium-Codex-Plugin-{version}.zip") as archive:
        installer = archive.getinfo("Galpium-Codex/Install Galpium Plugin.command")
        assert installer.external_attr >> 16 & stat.S_IXUSR, "Installer must be executable"
        archive.extractall(root / "package with spaces")
    package = root / "package with spaces/Galpium-Codex"
    # Codex deliberately filters its inherited environment. Use the supported
    # MCP env configuration to select a disposable library and this app build.
    mcp_file = package / "plugin/.mcp.json"
    config = json.loads(mcp_file.read_text())
    config["mcpServers"]["galpium"]["env"] = {
        "GALPIUM_APP": str(project / "dist/Galpium.app"),
        "GALPIUM_LIBRARY": str(root / "library"),
        "GALPIUM_SEMANTIC_DISABLED": "1",
    }
    mcp_file.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
    home = root / "codex"
    home.mkdir()
    env = {**os.environ, "CODEX_HOME": str(home), "GALPIUM_APP": str(project / "dist/Galpium.app"), "GALPIUM_LIBRARY": str(root / "library"), "GALPIUM_SEMANTIC_DISABLED": "1"}
    for args in [["plugin", "marketplace", "add", str(package), "--json"],
                 ["plugin", "add", "galpium@galpium-local", "--json"]]:
        result = subprocess.run([str(runtime), *args], env=env, check=True, capture_output=True, text=True, timeout=15)
    installed = Path(json.loads(result.stdout)["installedPath"])
    process = subprocess.Popen([str(runtime), "app-server"], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def call(identifier, method, params):
        process.stdin.write((json.dumps({"id": identifier, "method": method, "params": params}) + "\n").encode())
        process.stdin.flush()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                assert selector.select(max(0, deadline - time.monotonic())), f"{method} timed out"
                line = process.stdout.readline()
                assert line, f"{method} closed stdout"
                response = json.loads(line)
                if response.get("id") == identifier:
                    assert "error" not in response, response
                    return response["result"]
        raise AssertionError(f"{method} timed out")

    try:
        call(1, "initialize", {"clientInfo": {"name": "galpium-plugin-check", "version": "1"}, "capabilities": {"experimentalApi": True}})
        process.stdin.write(b'{"method":"initialized"}\n')
        process.stdin.flush()
        detail = call(2, "plugin/read", {"pluginName": "galpium", "marketplacePath": str(package / ".agents/plugins/marketplace.json")})["plugin"]
        assert detail["summary"]["installed"] and detail["summary"]["enabled"], detail
        assert detail["mcpServers"] == ["galpium"], detail
        assert any(s["name"] == "galpium:galpium-wiki" for s in detail["skills"]), detail
        status = call(3, "mcpServerStatus/list", {"serverName": "galpium"})
        server = next(s for s in status["data"] if s["name"] == "galpium")
        assert not server.get("toolsError"), server
        assert len(server["tools"]) == 21, server
        assert server["serverInfo"]["name"] == "Galpium", server
        assert server["serverInfo"]["version"] == version, server
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()

    mcp = json.loads((installed / ".mcp.json").read_text())["mcpServers"]["galpium"]
    mcp_env = env
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "Galpium plugin check", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    ]
    result = subprocess.run([mcp["command"], *mcp["args"]], input="".join(json.dumps(r) + "\n" for r in requests), env=mcp_env, check=True, capture_output=True, text=True, timeout=15)
    responses = [json.loads(line) for line in result.stdout.splitlines()]
    assert all("error" not in r for r in responses), responses
    tools = next(r["result"]["tools"] for r in responses if r.get("id") == 2)
    assert len({t["name"] for t in tools}) == 21
    assert not result.stderr, result.stderr

print("PASS: shipped ZIP, native desktop MCP startup/discovery, enabled skill and 21-tool handshake without path substitution")
