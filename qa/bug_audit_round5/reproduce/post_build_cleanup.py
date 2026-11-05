from pathlib import Path
import json,hashlib,shutil
r=Path('/workspace/luno-review/bug-audit-round5');app=Path('/workspace/luno-chess/luno_chess')
assert (r/'pipeline-exit.txt').read_text().strip()=='0'
a=json.loads((r/'android/Luno-Chess-bug-audit-round5-debug-arm64/verification.json').read_text());p=Path(a['file'])
assert hashlib.file_digest(p.open('rb'),'sha256').hexdigest()==a['sha256']
commands=json.loads((r/'android/commands.json').read_text());assert commands[-1]['args']==['./gradlew','--stop'] and commands[-1]['exit']==0
before=shutil.disk_usage('/workspace').free;records=[]
root=app/'build/app/intermediates'
for p in sorted(root.rglob('debug'),key=lambda p:len(p.parts)):
 if p.is_dir():
  size=sum(x.stat().st_size for x in p.rglob('*') if x.is_file());records.append({'path':str(p),'bytes':size});shutil.rmtree(p)
after=shutil.disk_usage('/workspace').free
(r/'android/post-build-space-recovery.json').write_text(json.dumps({'canonical_apk_hash_verified':a['sha256'],'only_completed_rebuildable_debug_intermediates_removed':True,'gradle_stopped':True,'records':records,'free_before':before,'free_after':after},indent=2)+'\n')
print({'completed_rebuildable_directories_removed':len(records),'free_MiB':round(after/2**20)})
