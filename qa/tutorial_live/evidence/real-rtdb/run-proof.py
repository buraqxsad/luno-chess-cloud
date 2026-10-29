from pathlib import Path
import hashlib,json,os,re,socket,subprocess,time,urllib.request
root=Path(__file__).resolve().parent
assert not os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'),'Configured cloud credentials are forbidden for this local proof.'
env=os.environ.copy()
for key in ['HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy']:env.pop(key,None)
env.update(GCLOUD_PROJECT='demo-luno-premium-race',METADATA_SERVER_DETECTION='none',
 FIREBASE_DATABASE_EMULATOR_HOST='127.0.0.1:19000',LUNO_DB_EMULATOR_NAMESPACE='demo-luno-premium-race-default-rtdb')
env.pop('FIREBASE_AUTH_EMULATOR_HOST',None)

def connected():
 with socket.socket() as s:
  s.settimeout(.3)
  return s.connect_ex(('127.0.0.1',19000))==0
assert not connected(),'Port19000 already in use; do not touch an existing service.'

def rss(pid):
 try:
  lines=Path('/proc/'+str(pid)+'/status').read_text().splitlines()
  return int(next(line for line in lines if line.startswith('VmRSS:')).split()[1])
 except (OSError,StopIteration):return 0

def sanitize(path):
 data=path.read_text(errors='replace')
 out=[]
 for line in data.splitlines():
  if re.search(r'idToken|refreshToken|accessToken|Bearer |debug.?token|debug.?secret|eyJ[A-Za-z0-9_-]+\.',line,re.I):line='[authentication-bearing diagnostic withheld]'
  out.append(line)
 dest=path.with_name(path.name.replace('.private',''))
 dest.write_text('\n'.join(out)+'\n');path.unlink()

command=['java','-Xms32m','-Xmx192m','-XX:MaxMetaspaceSize=96m','-XX:ReservedCodeCacheSize=32m','-Xss256k','-XX:ActiveProcessorCount=2','-XX:+UseSerialGC','-Duser.language=en','-jar','/workspace/toolchains/firebase-emulators/firebase-database-emulator-v4.11.2.jar','--host','127.0.0.1','--port','19000','--single_project_mode','Warning']
result={'scope':'Real localhost RTDB4.11.2/Admin SDK transactions, provider response mocked; no Auth/Functions/production/staging/device acceptance.',
 'project':'demo-luno-premium-race','namespace':env['LUNO_DB_EMULATOR_NAMESPACE'],'host':'127.0.0.1:19000','java_command':command,'peak_combined_rss_kib':0,'runs':[],'source_provenance':json.loads((root/'source-provenance.json').read_text())}
server=None;worker=None;raw=root/'emulator.private.log';started=time.monotonic()
try:
 with raw.open('w') as stream:server=subprocess.Popen(command,cwd=root,env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT)
 deadline=time.monotonic()+25
 while not connected():
  if server.poll() is not None:raise RuntimeError('RTDB emulator exited before binding.')
  if time.monotonic()>deadline:raise TimeoutError('Local RTDB startup timeout.')
  time.sleep(.2)
 # Load the preserved real game rules into this isolated demo namespace only.
 rules=Path('/workspace/luno-chess/database.rules.production.json').read_bytes()
 request=urllib.request.Request('http://127.0.0.1:19000/.settings/rules.json?ns='+env['LUNO_DB_EMULATOR_NAMESPACE'],data=rules,headers={'Authorization':'Bearer owner','Content-Type':'application/json'},method='PUT')
 with urllib.request.urlopen(request,timeout=10) as response:assert response.status==200
 result['rules_sha256']=hashlib.sha256(rules).hexdigest();result['rules_loaded_http_status']=200
 for variant in ['baseline','fixed']:
  log=root/(variant+'.private.log')
  with log.open('w') as stream:worker=subprocess.Popen(['node',str(root/'premium-races.cjs'),variant],cwd='/workspace/luno-chess/functions',env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT)
  deadline=time.monotonic()+90
  while worker.poll() is None:
   used=rss(server.pid)+rss(worker.pid);result['peak_combined_rss_kib']=max(result['peak_combined_rss_kib'],used)
   if used>600*1024:raise MemoryError('Proof RSS budget600MiB exceeded.')
   if time.monotonic()>deadline:raise TimeoutError('Local SDK worker90s deadline exceeded.')
   time.sleep(.15)
  sanitize(log)
  data=(root/(variant+'.log')).read_text()
  counts={}
  for key in ['tests','pass','fail','skipped','cancelled']:
   hits=re.findall(r'^# '+key+r' (\d+)\s*$',data,re.M)
   if hits:counts[key]=int(hits[-1])
  rows=json.loads((root/(variant+'-observations.json')).read_text()) if (root/(variant+'-observations.json')).exists() else []
  result['runs'].append({'variant':variant,'exit_code':worker.returncode,'counts':counts,'observations':rows})
  worker=None
  print(json.dumps(result['runs'][-1]),flush=True)
 baseline,fixed=result['runs']
 assert baseline['exit_code']==1 and baseline['counts']=={'tests':3,'pass':0,'fail':3,'skipped':0,'cancelled':0}
 assert len(baseline['observations'])==3 and all(row['actual_after_refresh']!=row['expected'] for row in baseline['observations'])
 assert fixed['exit_code']==0 and fixed['counts']=={'tests':3,'pass':3,'fail':0,'skipped':0,'cancelled':0}
 assert len(fixed['observations'])==3 and all(row['actual_after_refresh']==row['expected'] for row in fixed['observations'])
 result['local_sdk_acceptance']='PASS; baseline3/3 reproduced failures, fixed3/3 passes'
except BaseException as error:
 result['error']=type(error).__name__+': '+str(error);result['local_sdk_acceptance']='FAIL/NOT COMPLETE';raise
finally:
 for process in [worker,server]:
  if process and process.poll() is None:
   process.terminate()
   try:process.wait(timeout=5)
   except subprocess.TimeoutExpired:process.kill();process.wait(timeout=3)
 if raw.exists():sanitize(raw)
 for p in root.glob('*.private.log'):sanitize(p)
 result['port19000_closed_after_cleanup']=not connected();result['elapsed_seconds']=round(time.monotonic()-started,3)
 (root/'results.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({key:result[key] for key in ['local_sdk_acceptance','peak_combined_rss_kib','port19000_closed_after_cleanup','elapsed_seconds']}),flush=True)
