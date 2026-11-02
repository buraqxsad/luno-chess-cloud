from pathlib import Path
import subprocess,json,re,sys,time,hashlib
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round2')
scope=sys.argv[1];out=r/('full-'+scope);out.mkdir(exist_ok=True)
working=repo/('functions' if scope=='backend' else 'functions/rules-v1')
files=sorted((working/('test' if scope=='backend' else 'dist/test')).glob('*.test.js'))
results=[];total={k:0 for k in ['tests','pass','fail','cancelled','skipped','todo']}
for file in files:
 start=time.monotonic();log=out/(file.name+'.log')
 with log.open('w') as stream:
  try:code=subprocess.run(['node',str(file)],cwd=working,stdout=stream,stderr=subprocess.STDOUT,timeout=300).returncode
  except subprocess.TimeoutExpired:code=124
 txt=log.read_text(errors='replace');counts={}
 for key in total:
  values=re.findall(r'^# '+key+r' (\d+)\s*$',txt,re.M)
  if values:counts[key]=int(values[-1])
 item={'file':str(file.relative_to(working)),'exit':code,'counts':counts,'elapsed_seconds':round(time.monotonic()-start,3),'log':log.name}
 if not counts or '# Subtest:' not in txt:item['assertions_observed']=False
 else:item['assertions_observed']=True
 results.append(item)
 for key in total:total[key]+=counts.get(key,0)
 summary={'scope':scope,'runner':'Each *.test.js executed directly in a fresh Node process; actual TAP case counts, no file-level wrapper acceptance.','files':len(results),'totals':total,'results':results,'all_pass':all(x['exit']==0 and x['counts'].get('fail',1)==0 and x['assertions_observed'] for x in results)}
 (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
 print(scope,file.name,code,counts.get('pass'),counts.get('fail'),flush=True)
assert summary['all_pass'], 'One or more direct test files failed, timed out, or exposed no per-case TAP.'
