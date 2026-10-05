#!/usr/bin/env python3
"""Verify real initialized stdio presence without modifying user libraries."""
import hashlib,json,os,subprocess,tempfile,time
from pathlib import Path
from test_mcp import Client
binary=Path('dist/Galpium.app/Contents/MacOS/galpium-mcp').resolve()
with tempfile.TemporaryDirectory(prefix='galpium-connection-') as temporary:
 root=Path(temporary).resolve()
 directory=Path(tempfile.gettempdir())/f'Galpium-connections-{os.getuid()}'/hashlib.sha256(str(root).encode()).hexdigest()[:32]
 def records():
  return [json.loads(p.read_text()) for p in directory.glob('*.json')]
 client=Client(binary,root)
 try:
  client.call('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'Codex connection test','version':'1'}})
  initial=records();assert len(initial)==1 and initial[0]['name']=='Codex connection test',initial
  first=initial[0]['updatedAt'];time.sleep(2.5)
  assert records()[0]['updatedAt']>first,'Idle connection lost its heartbeat'
  client.tool('list',{})
  assert records()[0]['isBusy'] is False
 finally: client.close()
 assert records()==[],'Closed client retained presence'
 probe=subprocess.Popen([str(binary),'--library',str(root)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 probe.stdin.write(json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'Galpium connection check','version':'1'}}})+'\n');probe.stdin.flush();assert probe.stdout.readline()
 assert records()==[],'Execution probe was reported as connected'
 probe.stdin.close();probe.wait(timeout=5)
 crashed=Client(binary,root)
 try:
  before=records();assert len(before)==1
  crashed.process.kill();crashed.process.wait(timeout=5)
  assert records()[0]['pid']==before[0]['pid']
  # Snapshot reader rejects dead PIDs immediately; this leftover is intentionally expired.
  record=records()[0];assert record['pid']==crashed.process.pid
 finally:
  for p in directory.glob('*.json'): p.unlink()
 print('PASS: initialized process, idle heartbeat, request completion, EOF cleanup, self-probe exclusion and abrupt-exit fixture')
