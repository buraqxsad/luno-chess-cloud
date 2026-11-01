from pathlib import Path
import hashlib,json,os,re,socket,subprocess,time,urllib.request,sys
r=Path(__file__).resolve().parent;repo=Path('/workspace/luno-chess')
variant=sys.argv[1];rules_path=Path(sys.argv[2])
assert variant in ['baseline','fixed']
assert not os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
env=os.environ.copy()
for k in ['HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy','FIREBASE_AUTH_EMULATOR_HOST']:env.pop(k,None)
env.update(GCLOUD_PROJECT='demo-luno-presence-erasure',METADATA_SERVER_DETECTION='none',FIREBASE_DATABASE_EMULATOR_HOST='127.0.0.1:19000')
ns='demo-luno-presence-erasure-default-rtdb'
def connected():
 with socket.socket() as s:s.settimeout(.2);return s.connect_ex(('127.0.0.1',19000))==0
assert not connected(),'Existing RTDB listener; do not disturb it.'
def rss(pid):
 try:return int(next(x for x in Path('/proc/'+str(pid)+'/status').read_text().splitlines() if x.startswith('VmRSS:')).split()[1])
 except:return 0
def sanitized(p):
 if not p.exists():return
 text=p.read_text(errors='replace');out=[]
 for line in text.splitlines():
  if re.search(r'idToken|refreshToken|accessToken|Bearer |debug.?token|debug.?secret|eyJ[A-Za-z0-9_-]+\.',line,re.I):line='[authentication-bearing diagnostic withheld]'
  out.append(line)
 p.with_name(p.name.replace('.private','')).write_text('\n'.join(out)+'\n');p.unlink()
cmd=['java','-Xms32m','-Xmx192m','-XX:MaxMetaspaceSize=96m','-XX:ReservedCodeCacheSize=32m','-Xss256k','-XX:ActiveProcessorCount=2','-XX:+UseSerialGC','-Duser.language=en','-jar','/workspace/toolchains/firebase-emulators/firebase-database-emulator-v4.11.2.jar','--host','127.0.0.1','--port','19000','--single_project_mode','Warning']
result={'variant':variant,'scope':'Real local RTDB security rules; Admin SDK databaseAuthVariableOverride client identities, no Auth/Functions/production.','rules_file':str(rules_path),'rules_sha256':hashlib.sha256(rules_path.read_bytes()).hexdigest(),'project':env['GCLOUD_PROJECT'],'namespace':ns,'peak_combined_rss_kib':0,'java_command':cmd};server=None;worker=None;started=time.monotonic()
try:
 with (r/(variant+'-emulator.private.log')).open('w') as f:server=subprocess.Popen(cmd,env=env,cwd=r,stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT)
 deadline=time.monotonic()+25
 while not connected():
  assert server.poll() is None,'RTDB exited before startup'
  if time.monotonic()>deadline:raise TimeoutError('RTDB startup')
  time.sleep(.15)
 req=urllib.request.Request('http://127.0.0.1:19000/.settings/rules.json?ns='+ns,data=rules_path.read_bytes(),headers={'Authorization':'Bearer owner','Content-Type':'application/json'},method='PUT')
 with urllib.request.urlopen(req,timeout=10) as response:assert response.status==200
 with (r/(variant+'.private.log')).open('w') as f:worker=subprocess.Popen(['node',str(repo/'functions/test/system-hunt-identity-presence.integration.js'),str(r/(variant+'-observations.json'))],env=env,cwd=repo/'functions',stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT)
 deadline=time.monotonic()+60
 while worker.poll() is None:
  used=rss(server.pid)+rss(worker.pid);result['peak_combined_rss_kib']=max(result['peak_combined_rss_kib'],used)
  if used>600*1024:raise MemoryError('RSS over600MiB')
  if time.monotonic()>deadline:raise TimeoutError('SDK proof deadline60s')
  time.sleep(.1)
 result['exit_code']=worker.returncode;sanitized(r/(variant+'.private.log'))
 text=(r/(variant+'.log')).read_text();counts={}
 for key in ['tests','pass','fail','skipped','cancelled']:
  hits=re.findall(r'^# '+key+r' (\d+)\s*$',text,re.M)
  if hits:counts[key]=int(hits[-1])
 result['counts']=counts
 print(json.dumps({'variant':variant,'counts':counts,'exit_code':worker.returncode}),flush=True)
finally:
 for p in [worker,server]:
  if p and p.poll() is None:
   p.terminate()
   try:p.wait(timeout=5)
   except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)
 for p in r.glob('*.private.log'):sanitized(p)
 result['port_closed']=not connected();result['elapsed_seconds']=round(time.monotonic()-started,3)
 (r/(variant+'-result.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'cleanup':result['port_closed'],'seconds':result['elapsed_seconds'],'rss_kib':result['peak_combined_rss_kib']}),flush=True)
