#!/usr/bin/env python3
"""Kill a real writer around a commit, then verify the recovered SQLite corpus."""
import os
import argparse
import json
import signal
import sqlite3
import tempfile
from pathlib import Path
from test_mcp import Client

parser = argparse.ArgumentParser()
parser.add_argument("--binary", type=Path, default=Path(__file__).resolve().parents[1] / "dist/Galpium.app/Contents/MacOS/galpium-mcp")
args = parser.parse_args()
for iteration in range(3):
    with tempfile.TemporaryDirectory(prefix="galpium-crash-") as directory:
        root = Path(directory)
        client = Client(args.binary, root)
        client.tool("ingest", {"slug": "source", "title": "원본", "body": "강제 종료 검증용 원본"})
        page = {"slug": "page", "title": "강제 종료 검증", "body": "처음", "sources": ["source"], "expected_revision": 0}
        client.tool("upsert", page)
        for revision in range(1, 10):
            client.tool("upsert", {**page, "body": f"committed-{revision}", "expected_revision": revision})
        request = {"jsonrpc": "2.0", "id": 999, "method": "tools/call", "params": {"name": "galpium_wiki_upsert", "arguments": {**page, "body": "중단 가능 변경" * 2000, "expected_revision": 10}}}
        client.process.stdin.write(json.dumps(request, ensure_ascii=False).encode() + b"\n")
        client.process.stdin.flush()
        client.process.send_signal(signal.SIGKILL)
        client.process.wait(timeout=10)
        client.process.stdin.close(); client.process.stdout.close(); client.process.stderr.close()
        recovered = Client(args.binary, root)
        current = recovered.tool("read", {"slug": "page"})["page"]
        assert current["revision"] in (10, 11)
        assert recovered.tool("history", {"slug": "page"})["total"] == current["revision"]
        assert recovered.tool("read", {"slug": "page", "revision": 10})["page"]["body"] == "committed-9"
        assert recovered.tool("read", {"slug": "source", "kind": "source"})["source"]["body"] == "강제 종료 검증용 원본"
        recovered.close()
        with sqlite3.connect(f"file:{root / 'wiki.sqlite3'}?mode=ro", uri=True) as db:
            assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
            assert db.execute("SELECT count(*) FROM revisions").fetchone()[0] == current["revision"]
print("PASS: three forced writer exits, WAL recovery, original preservation, complete revisions and database integrity")
