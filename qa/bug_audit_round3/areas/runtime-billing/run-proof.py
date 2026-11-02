from pathlib import Path
import argparse,hashlib,json,os,re,socket,subprocess,time,urllib.request
parser=argparse.ArgumentParser();parser.add_argument('--commit',required=True);parser.add_argument('--sha',required=True);args=parser.parse_args()
root=Path(__file__).resolve().parent;repo=Path('/workspace/luno-chess');commit=args.commit
assert not os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'),'Cloud credentials are forbidden for this local proof.'
diff_flag=Path('/workspace/luno-review/bug-audit-round3/differential/exit.txt')
wait_deadline=time.monotonic()+600
while not diff_flag.exists() or not diff_flag.read_text().strip():
 if time.monotonic()>wait_deadline:raise SystemExit('Differential completion not observed; no emulator started.')
 time.sleep(2)
assert diff_flag.read_text().strip()=='0','Differential did not pass; no emulator started.'
source=subprocess.check_output(['git','show',commit+':functions/index.js'],cwd=repo)
expected=args.sha
assert hashlib.sha256(source).hexdigest()==expected and (repo/'functions/index.js').read_bytes()==source
(root/'fixed-index.cjs').write_bytes(source)
(root/'source-target.json').write_text(json.dumps({'commit':commit,'index_sha256':expected},indent=2)+'\n')
env=os.environ.copy();env.update(GCLOUD_PROJECT='demo-luno-billing-fence-r3-final',METADATA_SERVER_DETECTION='none',FIREBASE_DATABASE_EMULATOR_HOST='127.0.0.1:19000',LUNO_DB_EMULATOR_NAMESPACE='demo-luno-billing-fence-r3-final-default-rtdb')
env.pop('FIREBASE_AUTH_EMULATOR_HOST',None)
def connected():
 with socket.socket() as s:s.settimeout(.2);return s.connect_ex(('127.0.0.1',19000))==0
assert not connected(),'Port19000 already in use; this proof will not touch an existing service.'
def rss(pid):
 try:return int(next(x for x in Path('/proc/'+str(pid)+'/status').read_text().splitlines() if x.startswith('VmRSS:')).split()[1])
 except (OSError,StopIteration):return 0
def sanitize(path):
 data=path.read_text(errors='replace');lines=[]
 for line in data.splitlines():
  if re.search(r'idToken|refreshToken|accessToken|Bearer |debug.?token|debug.?secret|eyJ[A-Za-z0-9_-]+\.',line,re.I):line='[authentication-bearing diagnostic withheld]'
  lines.append(line)
 path.with_name(path.name.replace('.private','')).write_text('\n'.join(lines)+'\n');path.unlink()
command=['java','-Xms32m','-Xmx192m','-XX:MaxMetaspaceSize=96m','-XX:ReservedCodeCacheSize=32m','-Xss256k','-XX:ActiveProcessorCount=2','-XX:+UseSerialGC','-Duser.language=en','-jar','/workspace/toolchains/firebase-emulators/firebase-database-emulator-v4.11.2.jar','--host','127.0.0.1','--port','19000','--single_project_mode','Warning']
result={'source_commit':commit,'source_index_sha256':expected,'scope':'Real localhost RTDB4.11.2/Admin SDK transactions. One exact-loopback condition change in memory in the actual bundled standalone transport; proxy env/headers and all DB transaction code unchanged. Google Play fake; no Auth/Functions/Android/production/staging/money.','namespace':env['LUNO_DB_EMULATOR_NAMESPACE'],'host':'127.0.0.1:19000','java_command':command,'peak_combined_rss_kib':0,'local_sdk_acceptance':'NOT RUN'}
server=None;worker=None;started=time.monotonic();raw=root/'emulator.private.log'
try:
 with raw.open('w') as stream:server=subprocess.Popen(command,cwd=root,env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT)
 deadline=time.monotonic()+20
 while not connected():
  if server.poll() is not None:raise RuntimeError('RTDB emulator exited before binding.')
  if time.monotonic()>deadline:raise TimeoutError('Local RTDB startup20s limit exceeded.')
  time.sleep(.15)
 rules=(repo/'database.rules.production.json').read_bytes()
 request=urllib.request.Request('http://127.0.0.1:19000/.settings/rules.json?ns='+env['LUNO_DB_EMULATOR_NAMESPACE'],data=rules,headers={'Authorization':'Bearer owner','Content-Type':'application/json'},method='PUT')
 opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 with opener.open(request,timeout=5) as response:assert response.status==200
 result['rules_sha256']=hashlib.sha256(rules).hexdigest();result['rules_loaded_status']=200
 with (root/'fixed.private.log').open('w') as stream:worker=subprocess.Popen(['node',str(root/'fences.cjs')],cwd=repo/'functions',env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT)
 deadline=min(time.monotonic()+35,started+34)
 while worker.poll() is None:
  used=rss(server.pid)+rss(worker.pid);result['peak_combined_rss_kib']=max(result['peak_combined_rss_kib'],used)
  if used>600*1024:raise MemoryError('Combined RSS600MiB limit exceeded.')
  if time.monotonic()>deadline:raise TimeoutError('SDK bounded final worker deadline exceeded.')
  time.sleep(.15)
 result['worker_exit']=worker.returncode;sanitize(root/'fixed.private.log')
 data=(root/'fixed.log').read_text();counts={}
 for key in ['tests','pass','fail','skipped','cancelled']:
  hits=re.findall(r'^# '+key+r' (\d+)\s*$',data,re.M)
  if hits:counts[key]=int(hits[-1])
 result['counts']=counts;result['observations']=json.loads((root/'observations.json').read_text()) if (root/'observations.json').exists() else []
 assert worker.returncode==0 and counts=={'tests':5,'pass':5,'fail':0,'skipped':0,'cancelled':0},'Actual SDK test failure; consult filtered fixed.log.'
 assert len(result['observations'])==5
 transport=json.loads((root/'transport-audit.json').read_text());assert transport['smoke_pass'] and transport['inherited_proxy_environment_unchanged'] and transport['selected_connections']>=2
 result['transport_audit']=transport;result['transport_provenance']=json.loads((root/'transport-provenance.json').read_text())
 assert (repo/'functions/index.js').read_bytes()==source,'Frozen runtime source changed during proof.'
 result['source_reverified_after_run']=True;result['transport_audit']=json.loads((root/'transport-audit.json').read_text());result['earlier_successful_baseline']='/workspace/luno-review/bug-audit-round2/runtime/sdk-proof-final/results.json';result['earlier_two_timeouts_preserved_at']='/workspace/luno-review/system-bug-hunt/economy/sdk-proof/';result['local_sdk_acceptance']='PASS'
except BaseException as error:
 result['error']=type(error).__name__+': '+str(error);result['local_sdk_acceptance']='FAIL/NOT COMPLETE'
finally:
 for process in [worker,server]:
  if process and process.poll() is None:
   process.terminate()
   try:process.wait(timeout=4)
   except subprocess.TimeoutExpired:process.kill();process.wait(timeout=2)
 for p in root.glob('*.private.log'):sanitize(p)
 result['port19000_closed_after_cleanup']=not connected();result['elapsed_seconds']=round(time.monotonic()-started,3)
 result['private_logs_remaining']=len(list(root.glob('*.private.log')))
 (root/'results.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({k:result[k] for k in ['local_sdk_acceptance','peak_combined_rss_kib','port19000_closed_after_cleanup','elapsed_seconds','private_logs_remaining']}),flush=True)
if result['local_sdk_acceptance']!='PASS':raise SystemExit(1)
