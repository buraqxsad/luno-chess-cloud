from pathlib import Path
import subprocess,json,re,hashlib,time
repo=Path('/workspace/luno-chess');out=Path('/workspace/luno-review/bug-audit-round2/security');src=repo/'functions/index.js'
files=['round2-security-notification-erasure','round2-security-report-conversation','v214-social-safety','v219-sidecar-social-integrity','retained-record-race','account-deletion-gate','account-metadata-erasure','v238-battle-v1-migration-erasure','v236-app-check-policy','request-deletion-race','public-profile-deletion-race','profile-deletion-race','v218-social-atomic','dm-receipt-race']
results=[];totals={k:0 for k in ['tests','pass','fail','skipped','cancelled']}
for name in files:
 p=repo/'functions/test'/(name+'.test.js');log=out/(name+'-final-actual.log');start=time.monotonic();before=hashlib.sha256(src.read_bytes()).hexdigest()
 with log.open('w') as stream:code=subprocess.run(['node',str(p)],cwd=repo/'functions',stdout=stream,stderr=subprocess.STDOUT,timeout=90).returncode
 text=log.read_text(errors='replace');counts={}
 for k in totals:
  hits=re.findall(r'^# '+k+r' (\d+)\s*$',text,re.M)
  if hits:counts[k]=int(hits[-1]);totals[k]+=counts[k]
 results.append({'file':p.name,'exit':code,'counts':counts,'elapsed':round(time.monotonic()-start,3),'index_sha256_at_start':before,'per_case_tap_observed':'# Subtest:' in text})
 (out/'final-focused-results.json').write_text(json.dumps({'files':len(results),'totals':totals,'results':results},indent=2)+'\n')
 print(name,code,counts,flush=True)
assert all(x['exit']==0 and x['counts'].get('fail',1)==0 and x['per_case_tap_observed'] for x in results)
