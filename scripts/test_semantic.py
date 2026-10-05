#!/usr/bin/env python3
"""Real local-model integration; disposable libraries only. No external embedding API."""
import argparse
import hashlib
import json
import os
import selectors
import signal
import socket
import sqlite3
import subprocess
import tempfile
import time
from pathlib import Path
from test_mcp import Client

class SemanticClient(Client):
    def response(self):
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        if not selector.select(40):
            self.process.kill()
            raise AssertionError('Semantic MCP timed out')
        line = self.process.stdout.readline()
        selector.close()
        assert line, self.process.stderr.read().decode()
        return json.loads(line)

def socket_path(root):
    return f'/private/tmp/Galpium-{os.getuid()}/' + hashlib.sha256(str(root.resolve()).encode()).hexdigest()[:24] + '.sock'

def worker(root, operation):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(30)
        connection.connect(socket_path(root))
        connection.sendall((json.dumps({'operation': operation}) + '\n').encode())
        with connection.makefile('r') as stream: return json.loads(stream.readline())

def descendants(pid):
    rows = subprocess.check_output(['ps', '-axo', 'pid=,ppid='], text=True)
    processes = [tuple(map(int, row.split())) for row in rows.splitlines()]
    owned = {pid}
    while True:
        children = {child for child, parent in processes if parent in owned}
        if children <= owned: return owned - {pid}
        owned |= children

def wait_exited(pids):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        alive = set(map(int, subprocess.check_output(['ps', '-axo', 'pid='], text=True).split()))
        if not pids & alive: return
        time.sleep(.1)
    raise AssertionError('Owned inference processes did not exit: ' + str(pids & alive))

def wait_ready(client):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        result = client.tool('search', {'query': 'How do I preserve every revision and attached pictures?'})
        if result['retrieval']['semantic_status'] == 'ready': return result
        time.sleep(.15)
    raise AssertionError(result)

def main():
    os.environ.pop("GALPIUM_SEMANTIC_DISABLED", None)
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, default=Path(__file__).resolve().parents[1]/'dist/Galpium.app')
    parser.add_argument('--binary', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    if args.binary:
        binary = args.binary.resolve()
        os.environ.update({'GALPIUM_EMBEDDER': str(binary.parent/'galpium-embedder'),
                           'GALPIUM_EMBEDDING_RUNTIME': str(repo/'.build/vendor/Embedding/runtime/llama-server'),
                           'GALPIUM_EMBEDDING_MODEL': str(repo/'.build/vendor/Embedding/embeddinggemma-300M-Q8_0.gguf')})
    else: binary = args.app.resolve()/'Contents/MacOS/galpium-mcp'
    os.environ['GALPIUM_EMBEDDING_IDLE_SECONDS'] = '3'
    with tempfile.TemporaryDirectory(prefix='galpium-semantic-') as temporary:
        root = Path(temporary)
        a, b = SemanticClient(binary, root), SemanticClient(binary, root)
        try:
            empty = a.tool('search', {'query': 'backup'})
            assert empty['total'] == 0 and not Path(socket_path(root)).exists(), empty
            a.tool('ingest', {'slug': 'original', 'title': 'Immutable', 'body': 'original preserved'})
            page = {'slug': 'backup', 'title': '백업', 'body': '전체 백업에는 원본 자료와 모든 개정 이력, 첨부파일이 포함됩니다.', 'sources': ['original'], 'tags': ['operations'], 'expected_revision': 0}
            a.tool('upsert', page)
            a.tool('upsert', {**page, 'slug': 'coffee', 'title': 'コーヒー', 'body': 'ドリップコーヒーが苦すぎる場合は、挽き目を粗くするか抽出時間を短くします。', 'tags': ['daily']})
            result = wait_ready(a)
            assert result['items'][0]['slug'] == 'backup', result
            assert result['retrieval']['mode'] == 'hybrid'
            assert result['items'][0]['match']['revision'] == 1
            pid = worker(root, 'status')['workerPID']
            japanese = b.tool('search', {'query': 'How can I make my coffee less bitter?', 'tag': 'daily'})
            assert [x['slug'] for x in japanese['items']] == ['coffee'], japanese
            assert worker(root, 'status')['workerPID'] == pid, 'Clients created duplicate workers'
            assert a.tool('search', {'query': 'backup', 'tag': 'missing'})['total'] == 0
            a.tool('archive', {'slug': 'backup', 'expected_revision': 1})
            assert all(x['slug'] != 'backup' for x in b.tool('search', {'query': 'recover all old edits'})['items'])
            archived = a.tool('search', {'query': '백업', 'status': 'archived'})
            assert archived['items'][0]['slug'] == 'backup'
            assert archived['retrieval']['semantic_status'] == 'not_applicable'
            a.tool('restore', {'slug': 'backup', 'revision': 1, 'expected_revision': 2})
            wait_ready(a)
            assert a.tool('read', {'slug': 'original', 'kind': 'source'})['source']['body'] == 'original preserved'
            assert a.tool('history', {'slug': 'backup'})['total'] == 3
            # The supervisor must release the model if the worker is killed.
            pid = worker(root, 'status')['workerPID']
            inference = descendants(pid)
            assert len(inference) == 2, inference  # supervisor and native model runtime
            os.kill(pid, signal.SIGKILL)
            wait_exited(inference)
            restarted = wait_ready(b)
            assert restarted['items'][0]['slug'] == 'backup'
            assert worker(root, 'status')['workerPID'] != pid
            # Corrupt derived vectors must be regenerated without changing source/history.
            cache = root/'search-cache/embedding.sqlite3'
            with sqlite3.connect(cache) as db: db.execute("update vectors set vector='corrupt'")
            rebuilt = wait_ready(a)
            assert rebuilt['items'][0]['slug'] == 'backup'
            assert a.tool('history', {'slug': 'backup'})['total'] == 3
            pid = worker(root, 'status')['workerPID']
            owned = {pid} | descendants(pid)
            a.close(); b.close()
            time.sleep(4.5)
            assert not Path(socket_path(root)).exists(), 'Idle worker did not exit'
            wait_exited(owned)
            c = SemanticClient(binary, root)
            reused = wait_ready(c)
            assert reused['items'][0]['slug'] == 'backup'
            c.close()
            try: worker(root, 'shutdown')
            except (FileNotFoundError, ConnectionRefusedError): pass
        finally:
            for client in (a, b):
                if client.process.poll() is None:
                    client.process.terminate(); client.process.wait(timeout=5)
            try: worker(root, 'shutdown')
            except (OSError, ValueError): pass
    print('PASS: offline multilingual MCP retrieval, filters, current revisions, two clients/one worker, immutable originals, crash restart, corrupt-vector rebuild, idle release and cache reuse')

if __name__ == '__main__': main()
