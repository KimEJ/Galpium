#!/usr/bin/env python3
"""Pinned, checksum-verified offline multimodal model and native runtime; no installs."""
import hashlib
import json
import os
import platform
import shutil
import tarfile
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = root / '.build/vendor/Embedding'
assets = root / '.build/vendor/downloads'
output.mkdir(parents=True, exist_ok=True)
assets.mkdir(parents=True, exist_ok=True)
model = 'embeddinggemma-2-Q8_0.gguf'
model_sha = '2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135'
projector = 'mmproj-embeddinggemma-2-Q8_0.gguf'
projector_sha = 'c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f'
model_rev = 'bfcd298762cc34d0357ece5ebdd31791a3a374d8'
source_rev = '914f7f89142e33e77833254d9c9b90c3cef7303b'
runtime_version = 'b11468'
commit = 'b7dafa01e5f375c3010fb24b61a67329f957426a'
identity = model_sha + ':' + projector_sha + ':multimodal-v3:384:title80:prefix128:jpeg2048:audio20mono16k'


def get(url):
    return urllib.request.urlopen(
        urllib.request.Request(url, headers={'User-Agent': 'Galpium-build/0.0.2'}), timeout=60)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for data in iter(lambda: source.read(1024 * 1024), b''):
            result.update(data)
    return result.hexdigest()


def download(url, path, sha):
    if path.exists() and digest(path) == sha:
        return
    cached = assets / path.name
    if not cached.exists() or digest(cached) != sha:
        partial = cached.with_suffix(cached.suffix + '.partial')
        with get(url) as response, partial.open('wb') as target:
            shutil.copyfileobj(response, target, 1024 * 1024)
        if digest(partial) != sha:
            raise RuntimeError('Checksum mismatch: ' + str(path))
        partial.replace(cached)
    if cached != path:
        shutil.copy2(cached, path)


for filename, checksum in [(model, model_sha), (projector, projector_sha)]:
    download(
        f'https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/{model_rev}/{filename}',
        output / filename, checksum)
# Keep the offline payload specific to this release when reusing an older build folder.
(output / 'embeddinggemma-300M-Q8_0.gguf').unlink(missing_ok=True)
arch = {'arm64': 'arm64', 'x86_64': 'x64'}[platform.machine()]
name = f'llama-{runtime_version}-bin-macos-{arch}.tar.gz'
sha = {
    'arm64': 'b14f61716c7bbe13f4526d64e113f2f4b3771f3a694a66af93eec69ab1e6df80',
    'x64': '0204a42cc9490fd12ac5ea8d5b04ead25de9b2d8ff71937ffbe39847a4c80f8d',
}[arch]
archive = assets / name
download(f'https://github.com/ggml-org/llama.cpp/releases/download/{runtime_version}/{name}', archive, sha)
unpacked = assets / f'llama-{runtime_version}-{arch}'
if not unpacked.exists():
    partial = unpacked.with_name(unpacked.name + '.partial')
    if partial.exists():
        shutil.rmtree(partial)
    partial.mkdir()
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            parts = Path(member.name).parts
            if (member.name.startswith('/') or '..' in parts
                    or (member.issym() and (member.linkname.startswith('/')
                        or '..' in Path(member.linkname).parts))):
                raise RuntimeError('Unsafe runtime archive')
        tar.extractall(partial, filter='data')
    partial.replace(unpacked)
source = next(unpacked.rglob('llama-server')).parent
runtime = output / 'runtime'
if runtime.exists():
    shutil.rmtree(runtime)
runtime.mkdir()
for path in source.iterdir():
    if path.name == 'llama-server' or path.name.endswith('.dylib'):
        if path.is_symlink():
            (runtime / path.name).symlink_to(os.readlink(path))
        else:
            shutil.copy2(path, runtime / path.name)
licenses = output / 'licenses'
licenses.mkdir(exist_ok=True)
shutil.copy2(source / 'LICENSE', licenses / 'llama.cpp-LICENSE.txt')

# Refresh all vendor notices when the pinned runtime changes.
manifest_file = licenses / 'vendor-manifest.json'
try:
    prior_commit = json.loads(manifest_file.read_text())['commit']
except (OSError, ValueError, KeyError):
    prior_commit = None
refresh_notices = prior_commit != commit
if refresh_notices:
    for path in licenses.glob('vendor-*'):
        path.unlink()
    with get(f'https://api.github.com/repos/ggml-org/llama.cpp/git/trees/{commit}?recursive=1') as response:
        tree = json.load(response)
    if tree.get('truncated'):
        raise RuntimeError('Incomplete runtime license inventory')
    selected = [entry['path'] for entry in tree['tree']
                if entry['type'] == 'blob' and entry['path'].startswith('vendor/')
                and (Path(entry['path']).name.upper().startswith('LICENSE')
                     or Path(entry['path']).name.upper().startswith('COPYING'))]
    for item in selected:
        with get(f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{commit}/{item}') as response:
            (licenses / ('vendor-' + item.replace('/', '-'))).write_bytes(response.read())
else:
    selected = json.loads(manifest_file.read_text())['paths']

# Single-file libraries carry their license notices in the source header/footer.
for path, name in [('vendor/nlohmann/json.hpp', 'vendor-nlohmann-json.hpp.txt'),
                   ('vendor/miniaudio/miniaudio.h', 'vendor-miniaudio-LICENSE.txt')]:
    dest = licenses / name
    if not dest.exists():
        with get(f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{commit}/{path}') as response:
            text = response.read().decode()
        if 'miniaudio' in path:
            marker = '/*\nThis software is available as a choice of the following licenses.'
            start = text.rfind(marker)
            if start < 0:
                raise RuntimeError('Embedded license changed: ' + path)
            text = text[start:]
        dest.write_text(text)
manifest_file.write_text(json.dumps({'commit': commit, 'paths': selected}, indent=2) + '\n')

# EmbeddingGemma 2 is Apache-2.0; previous generation Gemma Terms do not describe it.
for name in ['Gemma-Terms.txt', 'Gemma-Prohibited-Use-Policy.txt', 'Model-Use-Terms.txt']:
    (licenses / name).unlink(missing_ok=True)
download('https://www.apache.org/licenses/LICENSE-2.0.txt', licenses / 'EmbeddingGemma-2-LICENSE.txt',
         'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30')
download(f'https://huggingface.co/google/embeddinggemma-2/raw/{source_rev}/README.md',
         licenses / 'EmbeddingGemma-2-MODEL-CARD.md',
         'b677a0ee2818c36f091b65fd3d9b4baea9f04d53b02b49cae916c74bf9682037')
(licenses / 'NOTICE.txt').write_text(
    'EmbeddingGemma 2: Google DeepMind, distributed under Apache License 2.0.\n'
    f'Original model revision: {source_rev}.\n'
    f'Q8_0 text, vision and audio GGUF conversion: ggml-org revision {model_rev}.\n'
    'Galpium bundles these GGUF files without modifying the weights.\n'
    'The model card is retained with its recommended use and limitations.\n'
    'llama.cpp and its bundled vendors retain their accompanying licenses.\n'
    'Galpium application code has its separate Apache-2.0 license.\n')
(output / 'manifest.json').write_text(json.dumps({
    'model': 'EmbeddingGemma 2 Q8_0', 'model_file': model,
    'model_filename': model, 'model_sha256': model_sha,
    'projector': projector, 'projector_file': projector, 'projector_sha256': projector_sha,
    'identity': identity,
    'modalities': ['text', 'image', 'audio'], 'model_revision': model_rev,
    'source_revision': source_rev, 'model_license': 'Apache-2.0',
    'runtime': 'llama.cpp ' + runtime_version, 'runtime_commit': commit,
    'runtime_sha256': sha, 'architecture': arch,
}, indent=2) + '\n')
print('Prepared offline EmbeddingGemma 2 and native runtime:', output)
