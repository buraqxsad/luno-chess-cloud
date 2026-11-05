from pathlib import Path
import gzip,hashlib,json,shutil,os,datetime
r=Path('/workspace/luno-review/bug-audit-round5');record=r/'snapshot-space.json';x=json.loads(record.read_text());p=Path(x['snapshot']);archive=Path(x['archive']);tmp=p.with_name('ram.bin.round5-restore.tmp')
def sha(path):
 with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
for proc in Path('/proc').iterdir():
 if not proc.name.isdigit():continue
 try:status=(proc/'status').read_text();name=next(v.split(':',1)[1].strip() for v in status.splitlines() if v.startswith('Name:'));state=next(v.split(':',1)[1].strip() for v in status.splitlines() if v.startswith('State:'))
 except (OSError,StopIteration):continue
 assert not ((name.startswith('qemu') or name=='emulator') and not state.startswith('Z')),'Emulator is active; no snapshot mutation.'
if p.exists():assert p.stat().st_size==x['original_bytes'] and sha(p)==x['original_sha256'],'Existing snapshot differs; do not overwrite.'
else:
 assert archive.is_file() and sha(archive)==x['archive_sha256']
 assert shutil.disk_usage('/workspace').free>x['original_bytes']+128*1024*1024,'Need additional free disk before restoring.'
 if tmp.exists():tmp.unlink() # only this helper's interrupted restore output
 with gzip.open(archive,'rb') as src,tmp.open('xb') as dest:shutil.copyfileobj(src,dest,1024*1024)
 assert tmp.stat().st_size==x['original_bytes'] and sha(tmp)==x['original_sha256']
 tmp.chmod(0o600);os.replace(tmp,p)
x['restore_required']=False;x['restored_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();x['restored_original_sha256']=sha(p);x['restored_original_bytes']=p.stat().st_size
record.write_text(json.dumps(x,indent=2)+'\n')
if archive.exists():archive.unlink()
x['archive_removed_after_restore']=True;x['free_after_restore']=shutil.disk_usage('/workspace').free;record.write_text(json.dumps(x,indent=2)+'\n')
a=r/'ACTIVE-WORK.json';v=json.loads(a.read_text());v['snapshot_ram_restore_required']=False;a.write_text(json.dumps(v,indent=2)+'\n')
print({'snapshot_restored_and_hash_verified':True,'bytes':p.stat().st_size,'free_MiB':round(x['free_after_restore']/2**20)})
