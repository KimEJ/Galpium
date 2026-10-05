#!/usr/bin/env python3
"""Bounded personal-library benchmark, synthetic data in a temporary library."""
import argparse
import json
import statistics
import tempfile
import time
from pathlib import Path
from test_mcp import Client

parser = argparse.ArgumentParser()
parser.add_argument("--binary", type=Path, default=Path(__file__).resolve().parents[1] / "dist/Galpium.app/Contents/MacOS/galpium-mcp")
parser.add_argument("--pages", type=int, default=500)
args = parser.parse_args()
assert 1 <= args.pages <= 10000
with tempfile.TemporaryDirectory(prefix="galpium-bench-") as directory:
    client = Client(args.binary, Path(directory))
    client.tool("ingest", {"slug": "source", "title": "합성 시험 자료", "body": "성능 검증용 합성 원본입니다."})
    start = time.perf_counter()
    for i in range(args.pages):
        client.tool("upsert", {"slug": f"document-{i}", "title": f"합성 문서 {i}", "body": ("배포 절차를 확인하고 재시작 결과를 기록합니다. " * 40) + f"\n문서식별자{i:05}", "sources": ["source"], "tags": ["합성"], "expected_revision": 0})
    write_seconds = time.perf_counter() - start
    timings = []
    for i in range(20):
        start = time.perf_counter()
        result = client.tool("search", {"query": f"문서식별자{i:05}"})
        timings.append((time.perf_counter() - start) * 1000)
        assert result["total"] == 1
    client.close()
print(json.dumps({"synthetic_pages": args.pages, "write_seconds": round(write_seconds, 3), "search_median_ms": round(statistics.median(timings), 3), "search_max_ms": round(max(timings), 3)}, indent=2))
