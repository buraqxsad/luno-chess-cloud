from pathlib import Path
import json,hashlib,zipfile,subprocess
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round4');out=r/'android';app=repo/'luno_chess';apk=r/'Luno-Chess-bug-audit-round4-debug-arm64.apk'
s=json.loads((r/'source-commit.json').read_text());recovery=json.loads((out/'package-audit-recovery.json').read_text())
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==s['build_source_commit']
assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo).strip()
assert hashlib.file_digest(apk.open('rb'),'sha256').hexdigest()==recovery['canonical_apk_sha256']
assert recovery['flutter_build_exit']==0 and recovery['canonical_apk_crc_verified']
commands=json.loads((out/'initial-package-audit/commands.json').read_text())
def run(args,cwd,name):
 with (out/name).open('w') as stream:code=subprocess.run(args,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT).returncode
 commands.append({'args':args,'cwd':str(cwd),'exit':code,'log':name,'source_commit':s['build_source_commit'],'stage':'resume_same_verified_apk'})
 (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');return code
assert run(['python3',str(out/'audit_apk.py'),str(apk)],repo,'debug-arm64-audit-resumed.log')==0
with zipfile.ZipFile(apk) as z:current=hashlib.sha256(z.read('assets/flutter_assets/kernel_blob.bin')).hexdigest()
with zipfile.ZipFile('/workspace/luno-review/bug-audit-round3/Luno-Chess-bug-audit-round3-debug-arm64.apk') as z:previous=hashlib.sha256(z.read('assets/flutter_assets/kernel_blob.bin')).hexdigest()
assert current!=previous
(out/'runtime-provenance.json').write_text(json.dumps({'source_commit':s['build_source_commit'],'file':apk.name,'payload':'assets/flutter_assets/kernel_blob.bin','sha256':current,'previous_round3_sha256':previous,'different_from_previous':True,'same_canonical_apk_after_space_recovery':True,'apk_sha256':recovery['canonical_apk_sha256'],'flutter_build_repeated':False},indent=2)+'\n')
code=run(['./gradlew',':app:validateLunoReleaseSigning','--offline'],app/'android','release-signing-guard.log');text=(out/'release-signing-guard.log').read_text(errors='replace')
status='BLOCKED' if code!=0 and 'Luno release signing unavailable' in text else 'REQUIRES REVIEW'
(out/'release-status.json').write_text(json.dumps({'source_commit':s['build_source_commit'],'guard_exit':code,'missing_existing_signing_identity_rejected':status=='BLOCKED','release_apk':status,'release_aab':status,'full_release_build':'NOT RUN when required signing prerequisite fails','signing_identity_changed':False,'play_upload':False},indent=2)+'\n')
assert run(['./gradlew','--stop'],app/'android','gradle-stop.log')==0
assert status=='BLOCKED'
print('Same completed APK audited; preserved first ENOSPC failure. Release prerequisite BLOCKED, no rebuild or identity change.',flush=True)
