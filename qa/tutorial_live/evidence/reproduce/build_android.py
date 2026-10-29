"""Build test APKs from the frozen code commit; never changes signing identity."""
from pathlib import Path
import hashlib, json, shutil, subprocess, os

repo=Path('/workspace/luno-chess');app=repo/'luno_chess';root=Path('/workspace/luno-review/tutorial-live')
expected=json.loads((root/'source-commit.json').read_text())['build_source_commit']
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==expected
assert subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True).strip()==''
assert (root/'analyze-final-exit.txt').read_text().strip()=='0'
assert (root/'availability-final-exit.txt').read_text().strip()=='0'
assert json.loads((root/'flutter/failure-classification.json').read_text())['all_failures_are_existing_pixel_comparisons']
records=[];cleanup=[]
def digest(p):
    with p.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def run(args,cwd,log):
    with (root/'android'/log).open('w') as stream:
        code=subprocess.run(args,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT).returncode
    records.append({'command':args,'exit_code':code,'log':log,'source_commit':expected})
    (root/'android/build-commands.json').write_text(json.dumps(records,indent=2)+'\n')
    return code

for mode,target,label in [('profile','android-x64','profile-x64'),('debug','android-arm64','debug-arm64')]:
    assert run(['flutter','build','apk','--'+mode,'--target-platform',target,'--build-number','19','--no-pub'],app,label+'-build.log')==0
    built=app/f'build/app/outputs/flutter-apk/app-{mode}.apk'
    artifact=root/f'Luno-Chess-tutorial-live-{label}.apk';shutil.copy2(built,artifact)
    assert digest(built)==digest(artifact)
    assert run(['python3',str(root/'android/audit_apk.py'),str(artifact)],repo,label+'-audit.log')==0
    # The canonical audited copy is immutable; remove only duplicate generated
    # outputs and completed variant intermediates to respect the 32GB disk.
    for path in list((app/'build/app/outputs').rglob('*.apk')):
        if digest(path)==digest(artifact):
            cleanup.append({'path':str(path),'bytes':path.stat().st_size});path.unlink()
    intermediate=app/'build/app/intermediates'
    for path in sorted(intermediate.rglob(mode),key=lambda p:len(p.parts),reverse=True):
        if path.is_dir():
            cleanup.append({'path':str(path),'bytes':sum(f.stat().st_size for f in path.rglob('*') if f.is_file())})
            shutil.rmtree(path)
    (root/'android/generated-cleanup.json').write_text(json.dumps(cleanup,indent=2)+'\n')
    print('Built and audited '+artifact.name,flush=True)

guard=run(['./gradlew',':app:validateLunoReleaseSigning','--offline'],app/'android','release-signing-guard.log')
text=(root/'android/release-signing-guard.log').read_text(errors='replace')
(root/'android/release-status.json').write_text(json.dumps({
    'source_commit':expected,'guard_exit':guard,
    'missing_signing_identity_rejected':guard!=0 and 'Luno release signing unavailable' in text,
    'release_aab':'BLOCKED' if guard!=0 and 'Luno release signing unavailable' in text else 'REQUIRES REVIEW',
    'release_apk':'BLOCKED' if guard!=0 and 'Luno release signing unavailable' in text else 'REQUIRES REVIEW',
    'full_release_builds':'NOT RUN when required signing prerequisite fails; no redundant compilation or fake key',
    'signing_identity_changed':False,'play_upload':False,'public_publication':False,
},indent=2)+'\n')
run(['./gradlew','--stop'],app/'android','gradle-stop.log')
import zipfile
provenance=[]
for mode,entry in [('profile-x64','lib/x86_64/libapp.so'),('debug-arm64','assets/flutter_assets/kernel_blob.bin')]:
    current=root/f'Luno-Chess-tutorial-live-{mode}.apk'
    previous=Path('/workspace/luno-review/v240')/f'Luno-Chess-v240-{mode}.apk'
    with zipfile.ZipFile(current) as z: current_hash=hashlib.sha256(z.read(entry)).hexdigest()
    with zipfile.ZipFile(previous) as z: previous_hash=hashlib.sha256(z.read(entry)).hexdigest()
    assert current_hash!=previous_hash, 'Current runtime must not be a renamed historical APK.'
    provenance.append({'file':current.name,'payload':entry,'sha256':current_hash,'v240_sha256':previous_hash,'different_from_v240':True})
(root/'android/runtime-payload-provenance.json').write_text(json.dumps({'source_commit':expected,'payloads':provenance},indent=2)+'\n')
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==expected
print('Final test APKs tied to '+expected+'; release prerequisite result recorded.',flush=True)
