from pathlib import Path
import hashlib,json,os,re,socket,subprocess,time,urllib.request
root=Path(__file__).resolve().parent;repo=Path('/workspace/luno-chess')
baseline='d627e06a963e6ab5f85d479ac53cbb161eb8ce3f'
assert not os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'),'No cloud credentials allowed.'
source=subprocess.check_output(['git','show',baseline+':functions/lib/battle-v1-friendly.js'],cwd=repo)
working_source=(repo/'functions/lib/battle-v1-friendly.js').read_bytes()
def scoped_bytes(value):
 text=value.decode();return [text[text.index(' async function transact('):text.index(' async function prepare(')],text[text.index(' async function respondBattleV1Invite('):text.index(' async function leaveAccount(')]]
assert scoped_bytes(working_source)==scoped_bytes(source)
(root/'captured-friendly.cjs').write_bytes(source)
target={'baseline_commit':baseline,'observed_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'friendly_sha256':hashlib.sha256(source).hexdigest(),'captured_friendly_matches_baseline':True,'working_friendly_sha256':hashlib.sha256(working_source).hexdigest(),'respond_transact_scope_matches_working_source':True,'dependencies':{}}
for name in ['functions/lib/battle-v1.js','functions/rules-v1/dist/src/online/protocol.js']:
 target['dependencies'][name]=hashlib.sha256((repo/name).read_bytes()).hexdigest()
(root/'source-target.json').write_text(json.dumps(target,indent=2)+'\n')
env=os.environ.copy();env.update(GCLOUD_PROJECT='demo-luno-cold-root-r3',METADATA_SERVER_DETECTION='none',FIREBASE_DATABASE_EMULATOR_HOST='127.0.0.1:19000',LUNO_DB_EMULATOR_NAMESPACE='demo-luno-cold-root-r3-default-rtdb')
env.pop('FIREBASE_AUTH_EMULATOR_HOST',None)
def connected():
 with socket.socket() as s:s.settimeout(.2);return s.connect_ex(('127.0.0.1',19000))==0
assert not connected(),'Port 19000 already occupied; refusing to use another service.'
def rss(pid):
 try:return int(next(x for x in Path('/proc/'+str(pid)+'/status').read_text().splitlines() if x.startswith('VmRSS:')).split()[1])
 except (OSError,StopIteration):return 0
def sanitize(path):
 lines=[]
 for line in path.read_text(errors='replace').splitlines():
  if re.search(r'idToken|refreshToken|accessToken|Bearer |debug.?token|debug.?secret|eyJ[A-Za-z0-9_-]+\.',line,re.I):line='[authentication-bearing diagnostic withheld]'
  lines.append(line)
 path.with_name(path.name.replace('.private','')).write_text('\n'.join(lines)+'\n');path.unlink()
command=['java','-Xms32m','-Xmx192m','-XX:MaxMetaspaceSize=96m','-XX:ReservedCodeCacheSize=32m','-Xss256k','-XX:ActiveProcessorCount=2','-XX:+UseSerialGC','-Duser.language=en','-jar','/workspace/toolchains/firebase-emulators/firebase-database-emulator-v4.11.2.jar','--host','127.0.0.1','--port','19000','--single_project_mode','Warning']
result={'source':target,'host':'127.0.0.1:19000','namespace':env['LUNO_DB_EMULATOR_NAMESPACE'],'java_command':command,'scope':'Local real Admin SDK/RTDB only. Exact-loopback proxy-selection condition changed in memory; inherited proxy env, SDK disk, data/transaction code unchanged. Admission/player/social/rate-limit dependencies stubbed; no production/test repo edits.','peak_combined_rss_kib':0,'local_sdk_result':'NOT RUN'}
server=None;worker=None;started=time.monotonic()
try:
 with (root/'emulator.private.log').open('w') as stream:server=subprocess.Popen(command,cwd=root,env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT)
 deadline=min(time.monotonic()+18,started+18)
 while not connected():
  result['peak_combined_rss_kib']=max(result['peak_combined_rss_kib'],rss(server.pid))
  if server.poll() is not None:raise RuntimeError('RTDB emulator stopped before bind.')
  if time.monotonic()>deadline:raise TimeoutError('Startup 18s limit exceeded.')
  time.sleep(.1)
 rules=(repo/'database.rules.production.json').read_bytes()
 request=urllib.request.Request('http://127.0.0.1:19000/.settings/rules.json?ns='+env['LUNO_DB_EMULATOR_NAMESPACE'],data=rules,headers={'Authorization':'Bearer owner','Content-Type':'application/json'},method='PUT')
 with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request,timeout=4) as response:assert response.status==200
 result['rules_sha256']=hashlib.sha256(rules).hexdigest()
 with (root/'proof.private.log').open('w') as stream:worker=subprocess.Popen(['node',str(root/'cold-root.cjs')],cwd=repo/'functions',env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT)
 deadline=min(time.monotonic()+22,started+37)
 while worker.poll() is None:
  used=rss(server.pid)+rss(worker.pid);result['peak_combined_rss_kib']=max(result['peak_combined_rss_kib'],used)
  if used>600*1024:raise MemoryError('Combined RSS 600MiB limit exceeded.')
  if time.monotonic()>deadline:raise TimeoutError('Bounded SDK worker deadline exceeded.')
  time.sleep(.1)
 result['worker_exit']=worker.returncode;sanitize(root/'proof.private.log')
 data=(root/'proof.log').read_text();counts={}
 for key in ['tests','pass','fail','skipped','cancelled']:
  hits=re.findall(r'^# '+key+r' (\d+)\s*$',data,re.M)
  if hits:counts[key]=int(hits[-1])
 result['counts']=counts
 result['observations']=json.loads((root/'observations.json').read_text()) if (root/'observations.json').exists() else []
 result['transport_audit']=json.loads((root/'transport-audit.json').read_text())
 result['transport_provenance']=json.loads((root/'transport-provenance.json').read_text())
 assert scoped_bytes((repo/'functions/lib/battle-v1-friendly.js').read_bytes())==scoped_bytes(source),'Friendly respond/transact changed during proof.'
 result['source_reverified_after_run']=True
 assert result['transport_audit']['smoke_pass'] and result['transport_audit']['inherited_proxy_environment_unchanged']
 assert counts=={'tests':4,'pass':3,'fail':1,'skipped':0,'cancelled':0},'Unexpected TAP outcome; do not treat as the anticipated source regression.'
 assert len(result['observations'])==4
 result['local_sdk_result']='CONFIRMED SOURCE BUG (3 controls pass, 1 intended behavior fails)'
except BaseException as error:
 result['error']=type(error).__name__+': '+str(error);result['local_sdk_result']='FAIL/NOT COMPLETE'
finally:
 for process in [worker,server]:
  if process and process.poll() is None:
   process.terminate()
   try:process.wait(timeout=3)
   except subprocess.TimeoutExpired:process.kill();process.wait(timeout=1)
 for p in root.glob('*.private.log'):sanitize(p)
 result['port19000_closed_after_cleanup']=not connected();result['elapsed_seconds']=round(time.monotonic()-started,3)
 result['private_logs_remaining']=len(list(root.glob('*.private.log')))
 (root/'results.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({k:result[k] for k in ['local_sdk_result','peak_combined_rss_kib','port19000_closed_after_cleanup','elapsed_seconds','private_logs_remaining']}),flush=True)
if result['local_sdk_result']=='FAIL/NOT COMPLETE':raise SystemExit(1)
