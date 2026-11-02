from pathlib import Path
import hashlib,json,subprocess,shutil,zipfile
repo=Path('/workspace/luno-chess');app=repo/'luno_chess';r=Path('/workspace/luno-review/bug-audit-round3');out=r/'android'
source=json.loads((r/'source-commit.json').read_text())['build_source_commit']
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==source
assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True).strip()
assert json.loads((r/'flutter/failure-classification.json').read_text())['all_failures_are_existing_pixel_comparisons']
assert json.loads((r/'full-backend/summary.json').read_text())['all_pass']
assert json.loads((r/'full-typescript/summary.json').read_text())['all_pass']
assert (r/'differential/exit.txt').read_text().strip()=='0'
commands=[]
def run(args,cwd,name):
 with (out/name).open('w') as stream:code=subprocess.run(args,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT).returncode
 commands.append({'args':args,'cwd':str(cwd),'exit':code,'log':name,'source_commit':source})
 (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');return code
assert run(['flutter','build','apk','--debug','--target-platform','android-arm64','--build-number','19','--no-pub'],app,'debug-arm64-build.log')==0
built=app/'build/app/outputs/flutter-apk/app-debug.apk';apk=r/'Luno-Chess-bug-audit-round3-debug-arm64.apk';shutil.copy2(built,apk)
assert run(['python3',str(out/'audit_apk.py'),str(apk)],repo,'debug-arm64-audit.log')==0
with zipfile.ZipFile(apk) as z:current_hash=hashlib.sha256(z.read('assets/flutter_assets/kernel_blob.bin')).hexdigest()
with zipfile.ZipFile('/workspace/luno-review/bug-audit-round2/Luno-Chess-bug-audit-round2-debug-arm64.apk') as z:previous_hash=hashlib.sha256(z.read('assets/flutter_assets/kernel_blob.bin')).hexdigest()
assert current_hash!=previous_hash
(out/'runtime-provenance.json').write_text(json.dumps({'source_commit':source,'file':apk.name,'payload':'assets/flutter_assets/kernel_blob.bin','sha256':current_hash,'previous_round2_sha256':previous_hash,'different_from_previous':True},indent=2)+'\n')
# Canonical audited artifact retained; remove only identical generated APK copies.
for p in (app/'build/app/outputs').rglob('*.apk'):
 if hashlib.sha256(p.read_bytes()).hexdigest()==hashlib.sha256(apk.read_bytes()).hexdigest():p.unlink()
guard=run(['./gradlew',':app:validateLunoReleaseSigning','--offline'],app/'android','release-signing-guard.log')
text=(out/'release-signing-guard.log').read_text(errors='replace')
status='BLOCKED' if guard!=0 and 'Luno release signing unavailable' in text else 'REQUIRES REVIEW'
(out/'release-status.json').write_text(json.dumps({'source_commit':source,'guard_exit':guard,'missing_existing_signing_identity_rejected':status=='BLOCKED','release_apk':status,'release_aab':status,'full_release_build':'NOT RUN when required signing prerequisite fails','signing_identity_changed':False,'play_upload':False},indent=2)+'\n')
run(['./gradlew','--stop'],app/'android','gradle-stop.log')
print('Built/audited current ARM64 test APK; release prerequisites recorded.',flush=True)
