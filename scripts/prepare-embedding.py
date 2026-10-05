#!/usr/bin/env python3
"""Pinned, checksum-verified native runtime and offline model; no package installs."""
import hashlib
import html.parser
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
model_sha = 'b5ce9d77a3fc4b3b39ccb5643c36777911cc4eb46a66962eadfa3f5f60490d63'
model_rev = '0f741b5a6585bd53aeb15cd1372c56f2a0f65e12'
commit = '99b95488cac0f00ce3f05af113a8c1e287753f87'

def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Galpium-build/0.2'}), timeout=60)

def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as f:
        for data in iter(lambda: f.read(1024 * 1024), b''): result.update(data)
    return result.hexdigest()

def download(url, path, sha):
    if path.exists() and digest(path) == sha: return
    partial = path.with_suffix(path.suffix + '.partial')
    with get(url) as response, partial.open('wb') as f: shutil.copyfileobj(response, f, 1024 * 1024)
    if digest(partial) != sha: raise RuntimeError('Checksum mismatch: ' + str(path))
    partial.replace(path)

model = 'embeddinggemma-300M-Q8_0.gguf'
download(f'https://huggingface.co/ggml-org/embeddinggemma-300M-GGUF/resolve/{model_rev}/{model}', output/model, model_sha)
arch = {'arm64': 'arm64', 'x86_64': 'x64'}[platform.machine()]
name = f'llama-b11371-bin-macos-{arch}.tar.gz'
sha = {
    'arm64': '92d7743775964bfecd576db2a24c41fc58a34877bd3c36f6ccf7e8bd735a8c4c',
    'x64': '9a981e72fb9003327b6a653a534d6bfd029e5240f13dd495dd939ab12581f7dd',
}[arch]
archive = assets/name
download(f'https://github.com/ggml-org/llama.cpp/releases/download/b11371/{name}', archive, sha)
unpacked = assets/f'llama-{arch}'
if not unpacked.exists():
    unpacked.mkdir()
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            parts = Path(member.name).parts
            if member.name.startswith('/') or '..' in parts or (member.issym() and (member.linkname.startswith('/') or '..' in Path(member.linkname).parts)):
                raise RuntimeError('Unsafe runtime archive')
        tar.extractall(unpacked, filter='data')
source = next(unpacked.rglob('llama-server')).parent
runtime = output/'runtime'
if runtime.exists(): shutil.rmtree(runtime)
runtime.mkdir()
for p in source.iterdir():
    if p.name == 'llama-server' or p.name.endswith('.dylib'):
        if p.is_symlink(): (runtime/p.name).symlink_to(os.readlink(p))
        else: shutil.copy2(p, runtime/p.name)
licenses = output/'licenses'
licenses.mkdir(exist_ok=True)
shutil.copy2(source/'LICENSE', licenses/'llama.cpp-LICENSE.txt')

# Include notices for vendored code in the native executable, not just its main license.
if not (licenses/'vendor-manifest.json').exists():
    with get(f'https://api.github.com/repos/ggml-org/llama.cpp/git/trees/{commit}?recursive=1') as response: tree=json.load(response)
    selected=[x['path'] for x in tree['tree'] if x['type']=='blob' and x['path'].startswith('vendor/') and (Path(x['path']).name.upper().startswith('LICENSE') or Path(x['path']).name.upper().startswith('COPYING'))]
    for item in selected:
        with get(f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{commit}/{item}') as response:
            (licenses/('vendor-'+item.replace('/','-'))).write_bytes(response.read())
    (licenses/'vendor-manifest.json').write_text(json.dumps({'commit':commit,'paths':selected},indent=2)+'\n')

# These single-file libraries embed notices instead of providing a LICENSE file.
# Retain JSON's complete header, including embedded third-party copyright notices.
for path,name in [('vendor/nlohmann/json.hpp','vendor-nlohmann-json.hpp.txt'),
                  ('vendor/miniaudio/miniaudio.h','vendor-miniaudio-LICENSE.txt')]:
    dest=licenses/name
    if not dest.exists():
        with get(f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{commit}/{path}') as response: data=response.read().decode()
        if 'miniaudio' in path:
            marker='/*\nThis software is available as a choice of the following licenses.'
            start=data.rfind(marker)
            if start<0: raise RuntimeError('Embedded license changed: '+path)
            data=data[start:]
        dest.write_text(data)

class Text(html.parser.HTMLParser):
    def __init__(self): super().__init__(); self.parts=[]; self.hidden=0
    def handle_starttag(self, tag, attrs):
        if tag in ('script','style'): self.hidden+=1
        if tag in ('p','div','h1','h2','h3','li','br'): self.parts.append('\n')
        if tag == 'a':
            self.link = dict(attrs).get('href','')
    def handle_endtag(self, tag):
        if tag in ('script','style'): self.hidden=max(0,self.hidden-1)
        if tag == 'a' and getattr(self,'link','').startswith('https://'): self.parts.append(' ('+self.link+')')
    def handle_data(self, data):
        if not self.hidden: self.parts.append(data)

for name,url,marker in [
 ('Gemma-Terms.txt','https://ai.google.dev/gemma/terms','Last modified: April 1, 2026'),
 ('Gemma-Prohibited-Use-Policy.txt','https://ai.google.dev/gemma/prohibited_use_policy','Gemma Prohibited Use Policy')]:
    dest=licenses/name
    if not dest.exists():
        with get(url) as response: page=response.read().decode()
        parser=Text();parser.feed(page);text=''.join(parser.parts)
        start=text.find(marker)
        if start<0: raise RuntimeError('License source changed: '+url)
        end=text.find('Except as otherwise noted',start)
        dest.write_text(url+'\n\n'+text[start:end if end>=0 else len(text)].strip()+'\n')
(licenses/'NOTICE.txt').write_text('EmbeddingGemma model: Google DeepMind. Q8_0 conversion: ggml-org.\n'
 'Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms.\n'
 'Use and distribution of the model are subject to the accompanying Gemma Terms and Prohibited Use Policy.\n'
 'Galpium bundles the ggml-org Q8_0 conversion without additional changes. Galpium application code has its separate Apache-2.0 license.\n')
(licenses/'Model-Use-Terms.txt').write_text('Use of Galpium’s bundled EmbeddingGemma component is subject to the accompanying Gemma Terms of Use.\nThe use restrictions in section 3.2, including the Gemma Prohibited Use Policy, are conditions of using this model component.\nDo not use the model for purposes prohibited by that policy or in violation of applicable laws.\nThese conditions apply to the model; the Galpium source code has its separate Apache-2.0 license.\n')
(output/'manifest.json').write_text(json.dumps({'model':'EmbeddingGemma 300M Q8_0','model_sha256':model_sha,'model_revision':model_rev,'runtime':'llama.cpp b11371','runtime_commit':commit,'runtime_sha256':sha,'architecture':arch},indent=2)+'\n')
print('Prepared offline EmbeddingGemma and native runtime:',output)
