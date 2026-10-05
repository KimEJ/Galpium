#!/usr/bin/env python3
"""Add clearly labeled sample content through Galpium's production MCP API."""
import argparse,base64,json,os,subprocess
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('--library',type=Path,required=True)
parser.add_argument('--binary',type=Path,default=Path('dist/Galpium.app/Contents/MacOS/galpium-mcp'))
parser.add_argument('--assets',type=Path,default=Path('dist/sample-assets'))
args=parser.parse_args()
env={**os.environ,'GALPIUM_SEMANTIC_DISABLED':'1'}
process=subprocess.Popen([str(args.binary.resolve()),'--library',str(args.library.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
request_id=0

def rpc(method,params):
 global request_id
 request_id+=1
 process.stdin.write(json.dumps({'jsonrpc':'2.0','id':request_id,'method':method,'params':params},ensure_ascii=False)+'\n');process.stdin.flush()
 line=process.stdout.readline()
 if not line: raise RuntimeError(process.stderr.read())
 result=json.loads(line)
 if 'error' in result: raise RuntimeError(result['error'])
 return result['result']

def tool(name,arguments):
 response=rpc('tools/call',{'name':'galpium_wiki_'+name,'arguments':arguments})
 if response.get('isError'): raise RuntimeError(response)
 return response['structuredContent']

rpc('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'Galpium samples','version':'1'}})
existing=tool('material_search',{'query':'샘플','status':'all','limit':100})['items']
materials={x['title']:x for x in existing}
def text(title,body):
 if title not in materials: materials[title]=tool('material_add',{'title':title,'body':body})['material']
 return materials[title]
def file(name):
 if name not in materials:
  materials[name]=tool('material_add',{'name':name,'base64':base64.b64encode((args.assets/name).read_bytes()).decode()})['material']
 return materials[name]
def page(slug,title,body,linked=(),citations=(),archive=False):
 # Samples never replace a page the user has already edited.
 try: tool('read',{'slug':slug}); return
 except RuntimeError: pass
 result=tool('upsert',{'slug':slug,'title':title,'body':body,'materials':[x['id'] for x in linked],'citations':list(citations),'tags':['샘플'],'expected_revision':0})
 if archive: tool('archive',{'slug':slug,'expected_revision':1})

try:
 korean=text('샘플 · 자료와 각주 안내','자료는 텍스트와 파일을 한 목록에서 관리합니다.\n\n각주는 원문 구절과 자료의 버전을 함께 보존합니다.\n\n직접 작성한 위키 문서는 자료 없이 저장할 수 있습니다.')
 japanese=text('샘플 · 日本語コーヒーメモ','ドリップコーヒーが苦すぎる場合は、挽き目を粗くするか抽出時間を短くします。\n\nこれは検索と引用を試すためのサンプル資料です。')
 english=text('샘플 · English backup notes','A full backup includes documents, preserved original materials, file bytes, and citation evidence.\n\nRestoring history creates a new revision instead of overwriting old revisions.')
 unused=text('샘플 · 연결하지 않은 자료','이 자료는 링크 수 0과 삭제 동작을 확인하기 위한 테스트 자료입니다.')
 archived=text('샘플 · 보관한 자료','보관함의 자료 필터에서 이 항목을 복원할 수 있습니다.')
 if archived['status']=='active': archived=tool('material_update',{'id':archived['id'],'status':'archived','expected_revision':archived['revision']})['material']
 pdf=file('샘플-위키-운영안내.pdf');image=file('샘플-자료연결.png');csv=file('샘플-비교표.csv')
 c1=tool('citation',{'material_id':korean['id'],'page':1,'quote':'각주는 원문 구절과 자료의 버전을 함께 보존합니다.','id':'sample-note'})
 page('sample-start','샘플 · 여기서 시작하세요','# 자료와 각주 테스트\n\n사이드바의 **자료**에서 텍스트·PDF·이미지·기타 파일을 확인하세요.\n\n원문 버전을 보존하는 인용을 지원합니다.[^sample-note]\n\n## 확인할 기능\n\n- 각주 번호를 누르고 **원문 보기**\n- 자료 이름 검색 및 링크 수\n- PDF 미리보기와 쪽별 텍스트\n- 보관함의 문서·자료 필터\n\n## 샘플 문서\n\n[[sample-backup|백업과 PDF 인용]]\n\n[[sample-coffee|다국어 검색]]\n\n![자료 연결](attachment:'+image['file_id']+')\n\n'+c1['footnote'],[korean,image],[c1['citation']])
 read=tool('material_read',{'id':pdf['id'],'page':2})
 quote=next(x.strip() for x in read['text'].splitlines() if 'Backups preserve' in x)
 c2=tool('citation',{'material_id':pdf['id'],'page':2,'quote':quote,'id':'sample-pdf'})
 page('sample-backup','샘플 · 백업과 PDF 인용','# 백업\n\n백업은 문서와 자료, 인용 근거를 보존합니다.[^sample-pdf]\n\n[[sample-start|시작 문서]]로 돌아갈 수 있습니다.\n\n[비교표](material:'+csv['id']+')\n\n'+c2['footnote'],[pdf,english,csv],[c2['citation']])
 c3=tool('citation',{'material_id':japanese['id'],'page':1,'quote':'ドリップコーヒーが苦すぎる場合は、挽き目を粗くするか抽出時間を短くします。','id':'sample-coffee'})
 page('sample-coffee','샘플 · 다국어 검색','# 커피 메모\n\n쓴맛을 줄이는 방법을 일본어 자료에서 확인할 수 있습니다.[^sample-coffee]\n\n자료 검색에서 “How can I make coffee less bitter?”로 찾아보세요.\n\n'+c3['footnote'],[japanese],[c3['citation']])
 page('sample-direct','샘플 · 직접 작성한 메모','# 직접 작성한 메모\n\n이 문서는 연결된 자료 없이 작성한 샘플입니다.\n\n편집한 뒤 저장해도 별도의 원본 자료가 자동 생성되지 않습니다.')
 page('sample-archived','샘플 · 보관한 문서','# 보관함\n\n문서 필터에서 이 샘플을 복원할 수 있습니다.',archive=True)
 print(json.dumps({'library':str(args.library),'sample_materials':len(materials),'sample_pages':5},ensure_ascii=False))
finally:
 process.stdin.close();process.wait(timeout=10)
