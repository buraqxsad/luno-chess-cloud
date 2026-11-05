from pathlib import Path
import gzip,hashlib,json,shutil,os,datetime
r=Path('/workspace/luno-review/bug-audit-round5');p=Path('/workspace/toolchains/avds/Luno_Android_10.avd/snapshots/luno-ready/ram.bin');archive=p.with_name('ram.bin.round5-parking.gz');record=r/'snapshot-space.json'
for proc in Path('/proc').iterdir():
 if not proc.name.isdigit():continue
 try:status=(proc/'status').read_text();name=next(x.split(':',1)[1].strip() for x in status.splitlines() if x.startswith('Name:'));state=next(x.split(':',1)[1].strip() for x in status.splitlines() if x.startswith('State:'))
 except (OSError,StopIteration):continue
 assert not ((name.startswith('qemu') or name=='emulator') and not state.startswith('Z')),'An emulator is active; snapshot remains untouched.'
assert p.exists() and not archive.exists() and not record.exists()
def sha(path):
 with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
original_sha=sha(p);original_bytes=p.stat().st_size;before=shutil.disk_usage('/workspace').free
with p.open('rb') as src,archive.open('xb') as dest:
 with gzip.GzipFile(filename='',fileobj=dest,mode='wb',compresslevel=1,mtime=0) as z:shutil.copyfileobj(src,z,1024*1024)
h=hashlib.sha256()
with gzip.open(archive,'rb') as src:
 for chunk in iter(lambda:src.read(1024*1024),b''):h.update(chunk)
assert h.hexdigest()==original_sha
x={'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Stopped emulator snapshot RAM temporarily losslessly parked for source tests/build disk. No raw memory content printed, uploaded or committed. No emulator boot.','snapshot':str(p),'archive':str(archive),'original_bytes':original_bytes,'original_sha256':original_sha,'archive_bytes':archive.stat().st_size,'archive_sha256':sha(archive),'roundtrip_verified_before_unlink':True,'restore_required':True,'free_before':before}
record.write_text(json.dumps(x,indent=2)+'\n');p.unlink();x['free_after']=shutil.disk_usage('/workspace').free;record.write_text(json.dumps(x,indent=2)+'\n')
a=r/'ACTIVE-WORK.json';v=json.loads(a.read_text());v['snapshot_ram_restore_required']=True;v['snapshot_parking_record']=str(record);a.write_text(json.dumps(v,indent=2)+'\n')
print({'original_MiB':round(original_bytes/2**20),'archive_MiB':round(x['archive_bytes']/2**20),'roundtrip_verified':True,'free_MiB':round(x['free_after']/2**20),'restore_required':True})
