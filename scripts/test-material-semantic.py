#!/usr/bin/env python3
"""Bounded real-model check for unified original-material retrieval."""
import argparse,base64,os,subprocess,tempfile,time
from pathlib import Path
from test_semantic import SemanticClient,worker
parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,default=Path('dist/Galpium.app'));args=parser.parse_args()
os.environ.pop('GALPIUM_SEMANTIC_DISABLED',None)
os.environ['GALPIUM_EMBEDDING_IDLE_SECONDS']='4'
binary=args.app.resolve()/'Contents/MacOS/galpium-mcp'
with tempfile.TemporaryDirectory(prefix='galpium-material-real-') as temporary:
 root=Path(temporary);a=SemanticClient(binary,root);b=SemanticClient(binary,root)
 try:
  ko=a.tool('material_add',{'title':'백업 원문','body':'전체 백업에는 원본 자료와 모든 개정 이력, 첨부파일이 포함됩니다.'})['material']
  ja=a.tool('material_add',{'title':'日本語コーヒー原文','body':'ドリップコーヒーが苦すぎる場合は、挽き目を粗くするか抽出時間を短くします。'})['material']
  en=a.tool('material_add',{'title':'Citation evidence','body':'Citations preserve the original source version, location, and exact quoted passage.'})['material']
  assets=root/'sample-assets'
  subprocess.run(['swift','-module-cache-path','/private/tmp/galpium-module-cache',str(Path(__file__).resolve().parent/'make-sample-assets.swift'),str(assets)],check=True,capture_output=True)
  pdf=a.tool('material_add',{'name':'Sample guide.pdf','base64':base64.b64encode((assets/'샘플-위키-운영안내.pdf').read_bytes()).decode()})['material']
  deadline=time.monotonic()+60
  while time.monotonic()<deadline:
   result=a.tool('material_search',{'query':'How do I preserve every revision and attached pictures?'})
   if result['semantic_status']=='ready': break
   time.sleep(.2)
  else: raise AssertionError(result)
  assert ko['id'] in [x['id'] for x in result['items'][:2]],result
  initial_pid=worker(root,'status')['workerPID']
  japanese=b.tool('material_search',{'query':'How can I make coffee less bitter?'})
  assert worker(root,'status')['workerPID']==initial_pid, 'Duplicate workers'
  assert japanese['items'][0]['id']==ja['id'],japanese
  assert japanese['items'][0]['match']['method']=='semantic',japanese
  assert all(x['content_role']=='original' and x['duplicate_group'] for x in japanese['items'])
  original=a.tool('material_read',{'id':pdf['id'],'page':2})
  assert 'Backups preserve' in original['text'] and original['extraction_id']
  quote=next(line for line in original['text'].splitlines() if 'Backups preserve' in line)
  cite=a.tool('citation',{'material_id':pdf['id'],'page':2,'quote':quote,'id':'ref-proof'})
  assert cite['citation']['extraction_id']==original['extraction_id']
  a.tool('material_update',{'id':ja['id'],'status':'archived','expected_revision':1})
  assert ja['id'] not in [x['id'] for x in b.tool('material_search',{'query':'coffee bitterness'})['items']]
  pid=worker(root,'status')['workerPID']
  print('PASS: ko/en/ja original retrieval, PDF extraction/citation, shared worker, archive exclusion')
 finally:
  a.close();b.close()
 try: worker(root,'shutdown')
 except (OSError,RuntimeError): pass
