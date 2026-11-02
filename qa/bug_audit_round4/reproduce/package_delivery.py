from pathlib import Path
import json,subprocess,hashlib,zipfile,datetime,gzip,re
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round4');q=repo/'qa/bug_audit_round4'
base='14780e10e9b511aababd009517507425890c4840';branch='codex/cloud-transfer-20261027'
source=json.loads((q/'source.json').read_text())['build_source_commit']
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True).strip()
assert subprocess.check_output(['git','branch','--show-current'],cwd=repo,text=True).strip()==branch
changes=subprocess.check_output(['git','diff','--name-only',source,head],cwd=repo,text=True).splitlines()
assert all(p=='DEVAM.md' or p.startswith('qa/bug_audit_round4/') for p in changes),changes
# Verify exact committed QA bytes and manifest completeness before making archives.
entries=[]
for line in (q/'EVIDENCE-SHA256SUMS').read_text().splitlines():
 sha,name=line.split('  ',1);p=q/name
 assert p.resolve().is_relative_to(q.resolve()) and p.is_file()
 assert hashlib.file_digest(p.open('rb'),'sha256').hexdigest()==sha,name
 entries.append(name)
assert set(entries)=={p.relative_to(q).as_posix() for p in q.rglob('*') if p.is_file() and p.name!='EVIDENCE-SHA256SUMS'}
tracked=set(subprocess.check_output(['git','ls-files','qa/bug_audit_round4'],cwd=repo,text=True).splitlines())
assert tracked=={p.relative_to(repo).as_posix() for p in q.rglob('*') if p.is_file()}
bundle=r/'Luno-Chess-bug-audit-round4-source.bundle'
subprocess.run(['git','bundle','create',str(bundle),base+'..'+branch],cwd=repo,check=True)
verify=subprocess.run(['git','bundle','verify',str(bundle)],cwd=repo,text=True,capture_output=True)
(r/'bundle-verification.log').write_text(verify.stdout+verify.stderr);assert verify.returncode==0
heads=subprocess.check_output(['git','bundle','list-heads',str(bundle)],cwd=repo,text=True)
assert head+' refs/heads/'+branch in heads
qa=r/'Luno-Chess-bug-audit-round4-qa.zip'
with zipfile.ZipFile(qa,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(q.rglob('*')):
  if p.is_file():z.write(p,p.relative_to(repo).as_posix())
with zipfile.ZipFile(qa) as z:
 assert z.testzip() is None
 assert set(z.namelist())==tracked
 for line in (q/'EVIDENCE-SHA256SUMS').read_text().splitlines():
  sha,name=line.split('  ',1)
  assert hashlib.sha256(z.read('qa/bug_audit_round4/'+name)).hexdigest()==sha
 zip_count=len(z.namelist())
artifacts=[]
for p in [r/'Luno-Chess-bug-audit-round4-debug-arm64.apk',bundle,qa]:
 sha=hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
 artifacts.append({'file':p.name,'bytes':p.stat().st_size,'sha256':sha})
a=json.loads((q/'android/apk-verification.json').read_text());assert artifacts[0]['sha256']==a['sha256']
f=json.loads((q/'flutter-summary.json').read_text());b=json.loads((q/'backend-summary.json').read_text())['totals'];ts=json.loads((q/'typescript-summary.json').read_text())['totals'];sdk=json.loads((q/'billing-sdk-summary.json').read_text())
(r/'SHA256SUMS').write_text(''.join(a['sha256']+'  '+a['file']+'\n' for a in artifacts))
summary={
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'build_source_commit':source,'delivery_commit':head,'branch':branch,
 'source_bundle_requires_base_commit':base,'source_bundle_verified':True,
 'qa_zip_crc_and_manifest_verified':True,'qa_zip_entries':zip_count,
 'only_qa_docs_changed_after_build':True,'git_worktree':'CLEAN','artifacts':artifacts,
 'fixed_new_bug_families':{'P1':1,'P2':3},'prior_family_residuals_fixed':{'P1':1,'P2':1},'concrete_defects_fixed':6,'new_verified_source_bugs_left_open_this_round':0,
 'global_bug_free_acceptance':'NOT ESTABLISHED',
 'flutter':{'pass':f['counts'].get('success',0),'fail':f['counts'].get('error',0),'skip':f['counts'].get('skip',0)},
 'backend':{'pass':b['pass'],'fail':b['fail'],'skip':b['skipped']},
 'typescript':{'pass':ts['pass'],'fail':ts['fail'],'skip':ts['skipped']},
 'local_real_sdk_billing':{'pass':sdk['counts']['pass'],'fail':sdk['counts']['fail'],'scope':sdk['scope']},
 'local_sdk_case_breakdown':{'billing_lease':6,'legacy_recovery':1},'flutter_source_commit':json.loads((q/'source.json').read_text())['flutter_regression_source_commit'],'historical_native_crash':'UNRESOLVED','historical_visual_differences':'FAIL',
 'release_decision':'HOLD','release_apk':'BLOCKED','release_aab':'BLOCKED',
 'current_apk_native_runtime':'NOT RUN','physical_device_perf':'NOT RUN','real_16kb_runtime':'NOT RUN',
 'production_firebase':'BLOCKED','licensed_play_billing':'BLOCKED','play_console':'BLOCKED',
 'github_push':False,'live_deploy':False,'real_money':False,'play_upload':False,'public_release':False}
(r/'DELIVERY.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
(r/'DELIVERY.md').write_text(f'''# Dördüncü sistem taraması teslimi — RELEASE HOLD

4 yeni hata ailesi (1 P1, 3 P2) ve önceki ailelerde kalan 2 yol (1 P1, 1 P2) kapatıldı: **6 somut düzeltme**.
Bu turda doğrulanıp açık bırakılan yeni kaynak kusuru: **0**. Bütün oyunda hatasızlık kanıtlanmadı.

Build/son Flutter kaynağı `{source}`; QA/devir commit’i `{head}`.
Dal `{branch}`. Çalışma ağacı temiz; build sonrası yalnız QA/devir belgeleri değişti.

- [ARM64 debug test APK’sı](Luno-Chess-bug-audit-round4-debug-arm64.apk): aynı debug sertifikası. Release/Play paketi değildir; yeni APK native cihazda oynatılmadı.
- [Kaynak bundle’ı](Luno-Chess-bug-audit-round4-source.bundle): mevcut Luno klonu için incremental Git bundle; `{base}` temel commit’ini gerektirir.
- [QA ZIP](Luno-Chess-bug-audit-round4-qa.zip): kök nedenler, 24 kart matrisi, önce/sonra kanıtları, ham loglar, widget görüntüleri ve kabul engelleri.
- [SHA-256](SHA256SUMS) · [Makine teslim kaydı](DELIVERY.json).

Mevcut klonda ayrı inceleme dalına almak için:

```bash
git bundle verify /path/Luno-Chess-bug-audit-round4-source.bundle
git fetch /path/Luno-Chess-bug-audit-round4-source.bundle refs/heads/{branch}:refs/heads/review/bug-audit-round4
git log --oneline review/bug-audit-round4 -8
```

Tam Flutter: {f['counts'].get('success',0)} geçti / {f['counts'].get('error',0)} tarihsel görsel başarısızlık /
{f['counts'].get('skip',0)} atlandı. Backend: {b['pass']} geçti / {b['fail']} başarısız / {b['skipped']} atlandı.
TypeScript: {ts['pass']} geçti / {ts['fail']} başarısız / {ts['skipped']} atlandı.
Gerçek yerel RTDB/Admin SDK: {sdk['counts']['pass']}/{sdk['counts']['tests']} geçti; Billing/lease 6 + legacy recovery 1.
Google yanıtları fake; bir exact loopback transport koşulu yalnız bellekte değişti. Üretim kabulü değildir.

97 golden farkı açık: 96 aday değişmedi, 1 aday Türkçe glif düzeltmesi için önce/sonra incelendi; golden değiştirilmedi.
Önceki native raster SIGSEGV, gerçek cihaz/performans/16 KB, mevcut upload imzası ve
Firebase/Google/Play/Console kabul kapıları açık. Release APK/AAB yok; **RELEASE HOLD**.
GitHub push, canlı deploy, para, Play upload ve yayın yapılmadı.
[Kaynak içi rapor](../../luno-chess/qa/bug_audit_round4/REPORT.md).
''')
print(json.dumps({'delivery_commit':head,'source_commit':source,'artifacts':artifacts,'qa_zip_entries':zip_count,'decision':'RELEASE HOLD'},ensure_ascii=False))
