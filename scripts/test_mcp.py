#!/usr/bin/env python3
"""Real stdio subprocess regression; uses only disposable temporary libraries."""
import argparse
import base64
import concurrent.futures
import json
import os
import selectors
import subprocess
import tempfile
import unicodedata
from pathlib import Path


class Client:
    def __init__(self, binary, root):
        self.process = subprocess.Popen([str(binary), "--library", str(root)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.sequence = 0
        self.call("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "galpium-regression", "version": "1"}})
        self.process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        self.process.stdin.flush()

    def response(self):
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        if not selector.select(10):
            self.process.kill()
            raise AssertionError("MCP response timed out")
        line = self.process.stdout.readline()
        selector.close()
        assert line, f"MCP closed stdout: {self.process.stderr.read().decode()}"
        return json.loads(line)

    def call(self, method, params=None):
        self.sequence += 1
        request = {"jsonrpc": "2.0", "id": self.sequence, "method": method, "params": params or {}}
        self.process.stdin.write(json.dumps(request, ensure_ascii=False).encode() + b"\n")
        self.process.stdin.flush()
        response = self.response()
        assert response["id"] == self.sequence, response
        assert "error" not in response, response
        return response["result"]

    def tool(self, name, arguments=None, error=False):
        result = self.call("tools/call", {"name": "galpium_wiki_" + name, "arguments": arguments or {}})
        assert result.get("isError", False) == error, result
        assert len(result["content"]) == 1 and result["content"][0]["type"] == "text"
        assert json.loads(result["content"][0]["text"]) == result["structuredContent"] if not error else True
        return result["structuredContent"]

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        assert self.process.returncode == 0
        stderr = self.process.stderr.read().decode(errors="replace")
        assert not stderr, f"MCP logged unexpected errors: {stderr}"


def main():
    os.environ["GALPIUM_SEMANTIC_DISABLED"] = "1"  # Keyword/protocol regression; real models have a separate suite.
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, default=Path(__file__).resolve().parents[1] / "dist/Galpium.app/Contents/MacOS/galpium-mcp")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="galpium-mcp-") as temporary:
        root = Path(temporary)
        a, b = Client(args.binary, root), Client(args.binary, root)
        tools = a.call("tools/list")["tools"]
        assert len(tools) == 21
        assert len({item["name"] for item in tools}) == 21
        a.tool("ingest", {"slug": "원본", "title": "시험 원본", "body": "배포 후 상태를 확인합니다.", "url": "https://example.com"})
        a.tool("ingest", {"slug": "원본", "title": "덮어쓰기", "body": "오류"}, error=True)
        page = {"slug": "운영", "title": "운영 절차", "body": "## 배포\n배포 상태 확인\n[원본](source:원본)", "sources": ["원본"], "tags": ["운영"], "pinned": True, "expected_revision": 0}
        assert a.tool("upsert", page)["page"]["revision"] == 1
        assert b.tool("read", {"slug": "운영"})["page"]["revision"] == 1
        changes = [{**page, "body": "첫 프로세스 수정", "expected_revision": 1}, {**page, "body": "둘째 프로세스 수정", "expected_revision": 1}]
        with concurrent.futures.ThreadPoolExecutor() as executor:
            futures = [executor.submit(client.call, "tools/call", {"name": "galpium_wiki_upsert", "arguments": change}) for client, change in zip([a, b], changes)]
            results = [future.result() for future in futures]
        assert sorted(item["isError"] for item in results) == [False, True]
        assert a.tool("history", {"slug": "운영"})["total"] == 2
        current = a.tool("read", {"slug": "운영"})["page"]
        upload = a.tool("attachment_add", {"name": "proof.txt", "base64": base64.b64encode(b"immutable bytes").decode()})
        assert upload["attachment"]["byte_count"] == 15
        new_body = current["body"] + f"\n[파일]({upload['reference']})\n[[다음]]"
        a.tool("upsert", {**page, "body": new_body, "expected_revision": 2})
        patch = {"slug": "운영", "expected_revision": 3, "replacements": [{"old_text": "프로세스", "new_text": "저장 프로세스"}], "change_note": "정확한 patch"}
        assert a.tool("patch", patch)["page"]["revision"] == 4
        assert a.tool("patch", patch)["page"]["revision"] == 4
        assert a.tool("attachments", {"slug": "운영"})["items"][0]["status"] == "available"
        assert a.tool("attachment_refs", {"file_id": upload["attachment"]["id"]})["total"] == 1
        assert a.tool("diff", {"slug": "운영", "from_revision": 1})["removed"] > 0
        assert a.tool("read", {"slug": "원본", "kind": "source"})["referenced_by"] == ["운영"]
        assert a.tool("search", {"query": unicodedata.normalize("NFD", "운영")})["total"] == 1
        assert a.tool("search", {"query": "없는 사실"})["retrieval"]["evidence_status"] == "insufficient"
        assert a.tool("list", {"tag": "운영%"})["total"] == 0
        assert a.tool("lint")["semantic_review_required"] is True
        assert a.tool("log")["total"] >= 5
        a.tool("archive", {"slug": "운영", "expected_revision": 4})
        assert a.tool("list")["total"] == 0
        assert a.tool("restore", {"slug": "운영", "revision": 1, "expected_revision": 5})["page"]["revision"] == 6
        assert a.tool("history", {"slug": "운영"})["total"] == 6
        a.process.stdin.write(b"not JSON\n"); a.process.stdin.flush()
        assert a.response()["error"]["code"] == -32700
        assert a.call("ping") == {}
        b.close(); a.close()
        reopened = Client(args.binary, root)
        assert reopened.tool("read", {"slug": "운영"})["page"]["revision"] == 6
        reopened.close()
    print("PASS: 21 tools, stdio negotiation, notifications, two writers, retry, conflicts, history, attachments and restart")


if __name__ == "__main__":
    main()
