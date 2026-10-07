#!/usr/bin/env python3
"""Bounded real-model product check; disposable library and native fixtures only.

These synthetic examples protect retrieval, provenance and process lifecycle.
They are not a model-quality benchmark or a claim about arbitrary media accuracy.
"""
import argparse
import base64
import hashlib
import json
import math
import os
import sqlite3
import struct
import subprocess
import tempfile
import time
import wave
from pathlib import Path

from test_semantic import (
    SemanticClient, cache_path, configure_assets, descendants, socket_path,
    wait_exited, worker,
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_tone(path):
    """Non-speech audio must not acquire an invented transcript or citation."""
    sample_rate = 16000
    frames = sample_rate * 3
    samples = bytearray()
    for index in range(frames):
        envelope = min(1, index / 400, (frames - index - 1) / 400)
        value = int(10000 * envelope * math.sin(2 * math.pi * 660 * index / sample_rate))
        samples.extend(struct.pack('<h', value))
    with wave.open(str(path), 'wb') as clip:
        clip.setnchannels(1)
        clip.setsampwidth(2)
        clip.setframerate(sample_rate)
        clip.writeframes(samples)


def add_file(client, path, name=None):
    data = path.read_bytes()
    assert len(data) <= 2 * 1024 * 1024, path
    item = client.tool('material_add', {
        'name': name or path.name,
        'base64': base64.b64encode(data).decode(),
    })['material']
    assert item['original_hash'] == hashlib.sha256(data).hexdigest(), item
    return item


def wait_materials(client, query, expected, state='ready', kind='all', timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = client.tool('material_search', {'query': query, 'kind': kind})
        indexed = {row['id'] for row in result['items'] if 'match' in row}
        if result['semantic_status'] == state and set(expected) <= indexed:
            if state == 'ready':
                assert result['indexed_materials'] == result['total_materials'], result
                assert result['failed_materials'] == 0 and result['pending'] is False, result
            elif state == 'partial':
                assert result['failed_materials'] == 1, result
                assert result['indexed_materials'] < result['total_materials'], result
                assert result['pending'] is True, result
            return result
        time.sleep(.2)
    raise AssertionError(result)


def wait_text_runtime(root):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        status = worker(root, 'status')
        if status.get('runtimeMode') == 'text':
            supervisor = status['supervisorPID']
            processes = descendants(supervisor)
            assert processes, status
            commands = subprocess.check_output(
                ['ps', '-p', ','.join(map(str, processes)), '-o', 'command='], text=True)
            assert 'llama-server' in commands and '--mmproj' not in commands, commands
            return status
        time.sleep(.2)
    raise AssertionError(status)


def visual_result(client, query, material_id, kind, page=None):
    result = client.tool('material_search', {'query': query, 'kind': kind})
    assert result['items'] and result['items'][0]['id'] == material_id, result
    match = result['items'][0]['match']
    assert match['method'] == 'visual' and match['modality'] == 'image', result
    if page is not None:
        assert match['page'] == page, result
    return result


def seed_old_cache(root):
    """A valid legacy database with conspicuous incompatible derived contents."""
    old = root / 'search-cache/embedding.sqlite3'
    old.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(old) as database:
        database.executescript('''
            CREATE TABLE vectors (id TEXT PRIMARY KEY, vector TEXT NOT NULL);
            CREATE TABLE passages (id TEXT, slug TEXT, digest TEXT, data TEXT);
            CREATE TABLE indexed (slug TEXT PRIMARY KEY, digest TEXT, revision INTEGER);
            INSERT INTO vectors VALUES ('old-vector', 'old-300m-incompatible-vector');
            INSERT INTO passages VALUES ('old-vector', 'material:old', 'old',
                '{"excerpt":"LEGACY MODEL POISON MUST NEVER BE RETURNED"}');
            INSERT INTO indexed VALUES ('material:old', 'old', 1);
        ''')
    return old, digest(old)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'dist/Galpium.app')
    parser.add_argument('--binary', type=Path)
    args = parser.parse_args()
    binary = configure_assets(args.app, args.binary)
    os.environ['GALPIUM_EMBEDDING_IDLE_SECONDS'] = '8'
    scripts = Path(__file__).resolve().parent
    clients = []
    with tempfile.TemporaryDirectory(prefix='galpium-material-real-') as temporary:
        root = Path(temporary)
        legacy, legacy_digest = seed_old_cache(root)
        try:
            a = SemanticClient(binary, root)
            b = SemanticClient(binary, root)
            clients.extend([a, b])
            assert a.tool('material_search', {'query': 'backup'})['total'] == 0
            assert not Path(socket_path(root)).exists(), 'Empty library loaded the model'
            assets = root / 'sample-assets'
            for script in ['make-sample-assets.swift', 'make-semantic-images.swift']:
                subprocess.run([
                    'swift', '-module-cache-path', '/private/tmp/galpium-module-cache',
                    str(scripts / script), str(assets),
                ], check=True, capture_output=True)
            make_tone(assets / 'asset-d.wav')
            ko = a.tool('material_add', {
                'title': '백업 원문',
                'body': '전체 백업에는 원본 자료와 모든 개정 이력, 첨부파일이 포함됩니다.',
            })['material']
            ja = a.tool('material_add', {
                'title': '日本語コーヒー原文',
                'body': 'ドリップコーヒーが苦すぎる場合は、挽き目を粗くするか抽出時間を短くします。',
            })['material']
            en = a.tool('material_add', {
                'title': 'Citation evidence',
                'body': 'Citations preserve the original source version, location, and exact quoted passage.',
            })['material']
            text_pdf = add_file(a, assets / '샘플-위키-운영안내.pdf', 'asset-e.pdf')
            apple = add_file(a, assets / 'asset-a.png')
            bicycle = add_file(a, assets / 'asset-b.png')
            scanned = add_file(a, assets / 'asset-c.pdf')
            tone = add_file(a, assets / 'asset-d.wav')
            assert tone['kind'] == 'audio', tone
            originals = [ko, ja, en, text_pdf, apple, bicycle, scanned, tone]
            result = wait_materials(a, 'How do I preserve every revision and attached pictures?',
                                    [item['id'] for item in originals])
            assert ko['id'] in [row['id'] for row in result['items'][:2]], result
            initial_pid = worker(root, 'status')['workerPID']
            for query, expected in [
                ('How can I make coffee less bitter?', ja),
                ('커피의 쓴맛을 줄이려면 어떻게 해야 하나요?', ja),
                ('引用は原文の版と正確な引用箇所を保存します', en),
            ]:
                result = b.tool('material_search', {'query': query, 'kind': 'text'})
                assert result['items'][0]['id'] == expected['id'], result
                assert result['items'][0]['match']['method'] == 'semantic', result
                assert all(row['content_role'] == 'original' and row['duplicate_group']
                           for row in result['items']), result
            assert worker(root, 'status')['workerPID'] == initial_pid, 'Duplicate workers'
            # Neutral filenames have no object words. The opposite image is a
            # hard negative; raster content is the only description of objects.
            for query, expected in [
                ('a red apple with a green leaf', apple),
                ('초록 잎이 달린 빨간 사과', apple),
                ('緑の葉がついた赤いリンゴ', apple),
                ('a blue bicycle with two wheels', bicycle),
                ('바퀴가 두 개 달린 파란 자전거', bicycle),
                ('青い自転車と二つの車輪', bicycle),
            ]:
                visual_result(b, query, expected['id'], 'image')
            visual_result(a, 'a red apple with a green leaf', scanned['id'], 'pdf', page=1)
            visual_result(b, 'a blue bicycle with two wheels', scanned['id'], 'pdf', page=2)
            text_result = a.tool('material_search', {
                'query': 'Backups preserve pages, original materials, and citation evidence.',
                'kind': 'pdf',
            })
            assert text_result['items'][0]['id'] == text_pdf['id'], text_result
            text_match = text_result['items'][0]['match']
            assert text_match['method'] == 'semantic' and text_match['modality'] == 'text', text_result
            assert text_match['page'] == 2, text_result
            # A bare filename is not a text passage. Pure image/audio/scan
            # originals must have only media-derived vectors in the cache.
            with sqlite3.connect(cache_path(root)) as database:
                for item in [apple, bicycle, scanned, tone]:
                    rows = database.execute(
                        'SELECT data FROM passages WHERE slug=?',
                        ('material:' + item['id'],),
                    ).fetchall()
                    assert rows and all(json.loads(row[0]).get('media') for row in rows), (item, rows)
            audio = b.tool('material_search', {
                'query': 'a high pitched electronic tone', 'kind': 'audio',
            })
            assert audio['items'][0]['id'] == tone['id'], audio
            audio_match = audio['items'][0]['match']
            assert audio_match['modality'] == 'audio' and audio_match['method'] == 'audio', audio
            assert audio_match['start_seconds'] == 0, audio
            assert 2.9 <= audio_match['end_seconds'] <= 3.1, audio
            for item in [apple, bicycle, scanned, tone]:
                original = a.tool('material_read', {'id': item['id']})
                assert not original['text_available'] and not original['text'], original
                assert original['material']['original_hash'] == item['original_hash'], original
                a.tool('citation', {
                    'material_id': item['id'], 'page': 1, 'quote': 'APPLE',
                }, error=True)
            # An actual text layer still supports exact quote citations.
            original = a.tool('material_read', {'id': text_pdf['id'], 'page': 2})
            assert 'Backups preserve' in original['text'] and original['extraction_id'], original
            quote = next(line for line in original['text'].splitlines()
                         if 'Backups preserve' in line)
            citation = a.tool('citation', {
                'material_id': text_pdf['id'], 'page': 2, 'quote': quote, 'id': 'ref-proof',
            })
            assert citation['citation']['extraction_id'] == original['extraction_id'], citation
            page = {
                'slug': 'fixture-notes', 'title': 'Fixture notes',
                'body': 'Saved original evidence.[^ref-proof]\n\n' + citation['footnote'],
                'materials': [apple['id'], text_pdf['id']],
                'citations': [citation['citation']], 'expected_revision': 0,
            }
            a.tool('upsert', page)
            a.tool('upsert', {**page, 'body': page['body'] + '\nAn additional note.',
                              'expected_revision': 1})
            assert a.tool('history', {'slug': 'fixture-notes'})['total'] == 2
            renamed = a.tool('material_update', {
                'id': apple['id'], 'title': 'asset-z.png', 'expected_revision': 1,
            })['material']
            assert renamed['original_hash'] == apple['original_hash'], renamed
            wait_materials(a, 'a red apple with a green leaf', [apple['id']], kind='image')
            visual_result(a, 'a red apple with a green leaf', apple['id'], 'image')
            a.tool('material_update', {
                'id': apple['id'], 'status': 'archived', 'expected_revision': 2,
            })
            active = b.tool('material_search', {'query': 'a red apple with a green leaf',
                                               'kind': 'image'})
            assert apple['id'] not in [row['id'] for row in active['items']], active
            archived = a.tool('material_search', {'query': 'asset-z', 'status': 'archived',
                                                 'kind': 'image'})
            assert archived['items'][0]['id'] == apple['id'], archived
            # A corrupt media original cannot stall a later valid original or
            # become title-only semantic evidence. Missing coverage stays partial.
            broken_path = assets / 'asset-f.png'
            broken_path.write_bytes(b'not a decoded image')
            broken = add_file(a, broken_path)
            after_failure = a.tool('material_add', {
                'title': 'Later source',
                'body': 'A lighthouse warns ships away from rocks with a rotating beam of light.',
            })['material']
            result = wait_materials(a, 'How does a lighthouse keep ships away from rocks?',
                                    [after_failure['id']], state='partial')
            assert result['items'][0]['id'] == after_failure['id'], result
            assert broken['id'] not in [row['id'] for row in result['items']], result
            a.tool('material_update', {
                'id': broken['id'], 'status': 'archived', 'expected_revision': 1,
            })
            wait_materials(a, 'How does a lighthouse keep ships away from rocks?',
                           [after_failure['id']])
            status = wait_text_runtime(root)
            assert status['workerPID'] == initial_pid, status
            assert cache_path(root).is_file(), cache_path(root)
            assert digest(legacy) == legacy_digest, 'First-generation cache was reused or changed'
            for item in originals:
                read = a.tool('material_read', {'id': item['id']})
                assert read['material']['original_hash'] == item['original_hash'], read
            assert a.tool('history', {'slug': 'fixture-notes'})['total'] == 2
            assert a.tool('read', {'slug': 'fixture-notes', 'revision': 1})['page']['body'] == page['body']
            owned = {initial_pid} | descendants(initial_pid)
            a.close()
            b.close()
            deadline = time.monotonic() + 14
            while Path(socket_path(root)).exists() and time.monotonic() < deadline:
                time.sleep(.2)
            assert not Path(socket_path(root)).exists(), 'Idle media worker did not exit'
            wait_exited(owned)
            c = SemanticClient(binary, root)
            clients.append(c)
            result = wait_materials(c, 'a blue bicycle with two wheels', [bicycle['id']], kind='image')
            assert result['items'][0]['id'] == bicycle['id'], result
            assert worker(root, 'status')['workerPID'] != initial_pid
            assert digest(legacy) == legacy_digest
            c.close()
        finally:
            for client in clients:
                if client.process.poll() is None:
                    client.process.terminate()
                    client.process.wait(timeout=5)
            try:
                worker(root, 'shutdown')
            except (OSError, ValueError):
                pass
    print('PASS: ko/en/ja text and visual retrieval, image-only PDF page provenance, audio window without invented transcript, exact text citations, original hashes/history, shared worker, versioned cache, rename/archive, partial failure recovery, text-only query runtime and idle restart')


if __name__ == '__main__':
    main()
