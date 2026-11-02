from pathlib import Path
import json,gzip,re,hashlib,shutil
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round3');q=repo/'qa/bug_audit_round3'
# Polish only the new handoff section; preserve all historical records.
p=repo/'DEVAM.md';txt=p.read_text();new,old=txt.split('## 2 Kasım — ikinci sistem taraması',1)
for a,b in {'differential3101senaryo/10967durum':'differential 3101 senaryo / 10967 durum','Billing5/5':'Billing 5/5','cold-friendly4/4':'cold-friendly 4/4','proxy/header/SDKdisk':'proxy/header/SDK disk','minSdk24/targetSdk36,750asset':'minSdk 24 / targetSdk 36, 750 asset','statik16KB':'statik 16 KB','gerçek Android yolculuğu/performans/16KB':'gerçek Android yolculuğu/performans/16 KB'}.items():new=new.replace(a,b)
p.write_text(new+'## 2 Kasım — ikinci sistem taraması'+old)
for name in ['update_handoff.py','finalize_qa.py']:
 shutil.copy2(r/name,q/'reproduce'/name)
patterns={
 'private_key':re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
 'google_api_key':re.compile(r'AIza[0-9A-Za-z_-]{30,}'),
 'jwt':re.compile(r'eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}'),
 'bearer_value':re.compile(r'Bearer\s+[A-Za-z0-9._-]{24,}'),
 'appcheck_debug_value':re.compile(r'(?:debug token|AppCheckDebugToken)\s*[:=]\s*[0-9a-f-]{32,}',re.I),
}
findings=[];broken=[];scanned=0
for p in q.rglob('*'):
 if not p.is_file() or p.suffix=='.png':continue
 text=gzip.open(p,'rt',errors='replace').read() if p.suffix=='.gz' else p.read_text(errors='replace');scanned+=1
 for label,pattern in patterns.items():
  n=len(pattern.findall(text))
  if n:findings.append({'file':str(p.relative_to(q)),'kind':label,'count':n})
 if p.suffix=='.md':
  for target in re.findall(r'\]\(([^)]+)\)',text):
   target=target.strip('<>').split('#')[0]
   if target and '://' not in target and not (p.parent/target).exists():broken.append({'file':str(p.relative_to(q)),'target':target})
assert not findings and not broken,(findings,broken)
(q/'evidence/qa-preflight.json').write_text(json.dumps({'text_files_scanned':scanned,'secret_pattern_findings':findings,'broken_markdown_links':broken},indent=2)+'\n')
manifest=[]
for p in sorted(q.rglob('*')):
 if p.is_file() and p.name!='EVIDENCE-SHA256SUMS':manifest.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(q).as_posix())
(q/'EVIDENCE-SHA256SUMS').write_text('\n'.join(manifest)+'\n')
print('Final QA manifest:',len(manifest),'files; secret/link checks clear.')
