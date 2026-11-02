from pathlib import Path
import gzip,re,json,hashlib,urllib.parse,subprocess
repo=Path('/workspace/luno-chess');q=repo/'qa/bug_audit_round4';r=Path('/workspace/luno-review/bug-audit-round4')
assert q.exists()
# Scan content without printing matched material.
patterns={
 'private_key':re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
 'jwt':re.compile(r'\beyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}'),
 'github_personal_token':re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{35,})'),
 'google_oauth_refresh':re.compile(r'(?<![A-Za-z0-9])1//[A-Za-z0-9_-]{50,}'),
}
findings=[];files=0;decompressed_bytes=0
for p in sorted(q.rglob('*')):
 if not p.is_file() or p.suffix in {'.png','.webp','.zip','.apk','.bundle'}:continue
 try:raw=gzip.decompress(p.read_bytes()) if p.suffix=='.gz' else p.read_bytes();text=raw.decode('utf8')
 except (UnicodeDecodeError,OSError):continue
 files+=1;decompressed_bytes+=len(raw)
 for label,pattern in patterns.items():
  n=len(pattern.findall(text))
  if n:findings.append({'file':p.relative_to(q).as_posix(),'pattern':label,'count':n})
link_findings=[];absolute_links=[]
for p in sorted(q.rglob('*.md')):
 for match in re.finditer(r'\]\(([^)]+)\)',p.read_text()):
  target=match[1].strip().strip('<>')
  if target.startswith(('http://','https://','mailto:','#','skill://')):continue
  target=urllib.parse.unquote(target.split('#',1)[0]);target=re.sub(r':\d+$','',target)
  candidate=Path(target) if target.startswith('/') else p.parent/target
  if target.startswith('/'):absolute_links.append({'file':str(p.relative_to(q)),'target':target,'exists':candidate.exists()})
  if not candidate.exists():link_findings.append({'file':str(p.relative_to(q)),'target':target})
record={'text_files_scanned':files,'decompressed_text_bytes':decompressed_bytes,'sensitive_pattern_findings':findings,'markdown_missing_targets':link_findings,'absolute_links':absolute_links,'matched_values_printed':False,'golden_references_changed':False}
(r/'evidence-review.json').write_text(json.dumps(record,indent=2)+'\n')
print({k:record[k] for k in ['text_files_scanned','decompressed_text_bytes','sensitive_pattern_findings','markdown_missing_targets']})
assert not findings,'Review sensitive-pattern file/count list without printing matched material.'
assert not link_findings,'Resolve evidence links before commit.'
# Trailing empty CJS lines in preserved evidence are archived, not silently edited.
for p in q.rglob('*.cjs'):
 if p.read_bytes().endswith(b'\n\n'):
  dest=Path(str(p)+'.gz')
  assert not dest.exists()
  with dest.open('wb') as f:
   with gzip.GzipFile(filename='',fileobj=f,mode='wb',mtime=0) as z:z.write(p.read_bytes())
  p.unlink()
for p in q.rglob('*.md'):
 text=p.read_text()
 def fix(m):
  path=p.parent/m[1]
  return ']('+m[1]+'.gz)' if not path.exists() and Path(str(path)+'.gz').exists() else m[0]
 p.write_text(re.sub(r'\]\(([^)]+)\)',fix,text))
# Manifest must be refreshed after every report/source-evidence edit.
(q/'EVIDENCE-SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(q).as_posix()+'\n' for p in sorted(q.rglob('*')) if p.is_file() and p.name!='EVIDENCE-SHA256SUMS'))
print('Evidence content/link scan passed; byte-preserving archives and manifest prepared.')
