from pathlib import Path
import json,hashlib,gzip,shutil,re,subprocess,datetime
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round3');q=repo/'qa/bug_audit_round3'
def data(name):return json.loads((r/name).read_text())
def write(name,text):
 p=q/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
def put(name,value):write(name,json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def copy(src,name):
 p=q/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,p)
def compressed(src,name):
 raw=src.read_text(errors='replace')
 raw=re.sub(r'Bearer\s+[A-Za-z0-9._-]{24,}','Bearer [withheld]',raw)
 raw=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[JWT withheld]',raw)
 p=q/(name+'.gz');p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('wb') as f:
  with gzip.GzipFile(filename='',fileobj=f,mode='wb',mtime=0) as z:z.write(raw.encode())
assert (r/'pipeline-exit.txt').read_text().strip()=='0'
assert (r/'android/pipeline-exit.txt').read_text().strip()=='0'
assert (r/'differential/exit.txt').read_text().strip()=='0'
assert (r/'analyze-final-exit.txt').read_text().strip()=='0'
s=data('source-commit.json');f=data('flutter/summary.json');b=data('full-backend/summary.json');ts=data('full-typescript/summary.json');d=data('differential/v201a-differential-summary.json');sdk=data('runtime-billing/results.json');cold=data('runtime/fixed-proof/results.json')
assert b['all_pass'] and ts['all_pass'] and f['done']
assert data('flutter/failure-classification.json')['all_failures_are_existing_pixel_comparisons']
assert sdk['local_sdk_acceptance']=='PASS' and sdk['counts']['pass']==5 and sdk['counts']['fail']==0
assert cold['counts']['pass']==4 and cold['counts']['fail']==0
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==s['build_source_commit']
assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo).strip()
assert not subprocess.check_output(['git','diff',s['flutter_regression_source_commit'],s['build_source_commit'],'--','luno_chess','functions/index.js','functions/lib'],cwd=repo).strip()
a=data('android/Luno-Chess-bug-audit-round3-debug-arm64/verification.json')
assert hashlib.file_digest(Path(a['file']).open('rb'),'sha256').hexdigest()==a['sha256'] and a['source_asset_files_verified']==750
assert data('android/release-status.json')['release_aab']=='BLOCKED'
for name,obj in [('source.json',s),('flutter-summary.json',f),('backend-summary.json',b),('typescript-summary.json',ts),('differential-summary.json',d),('billing-sdk-summary.json',sdk),('friendly-sdk-summary.json',cold)]:put(name,obj)
copy(r/'android/Luno-Chess-bug-audit-round3-debug-arm64/verification.json','android/apk-verification.json')
for name in ['baseline.json','flutter/failure-classification.json','flutter/golden-comparison.json','flutter/suite-outcomes.json','android/release-status.json','android/runtime-provenance.json','android/commands.json','android/disk-recovery.json','android/post-build-space-recovery.json','differential/source-provenance.json','pipeline-wait-restart.json','initial-final-attempt/CLASSIFICATION.json']:
 copy(r/name,'evidence/'+name)
for area in ['economy','online','security','client','battle','rules','runtime','runtime-billing']:
 for p in (r/area).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r/area).as_posix();target='areas/'+area+'/'+rel
  if p.name in {'fixed-index.cjs','baseline-index.cjs','canonical-baseline-index.cjs','candidate-index.cjs'}:continue
  if p.suffix in {'.log','.tap','.jsonl','.patch','.diff'}:compressed(p,target)
  elif p.suffix in {'.json','.md','.py','.cjs','.dart','.ts','.txt','.sh'}:copy(p,target)
for name in ['full-backend','full-typescript','differential','flutter','android','initial-final-attempt']:
 for p in (r/name).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r).as_posix()
  if p.suffix in {'.log','.tap','.jsonl'}:compressed(p,'logs/'+rel)
  elif name=='initial-final-attempt' and p.suffix in {'.json','.txt'}:copy(p,'evidence/'+rel)
for p in r.glob('*.log'):compressed(p,'logs/'+p.name)
for name in ['run_node_direct.py','summarize.py','post_tests.py','run_flutter_final.sh','finish_pipeline.sh','run_backend_final.sh','android/build_android.py','android/audit_apk.py','assemble_report.py','prepare_final_billing_sdk.py']:copy(r/name,'reproduce/'+name)
for lang in ['tr','en']:
 p=r/'generated/luno_chess/qa/v230/screens'/('guided-target-'+lang+'.png');assert p.exists();copy(p,'screenshots/guided-target-'+lang+'.png')
# Require the actual final per-card results, not merely a suite total.
tests={};suites={};outcomes={}
for line in (r/'flutter/full.jsonl').open():
 try:e=json.loads(line)
 except ValueError:continue
 if e.get('type')=='suite':suites[e['suite']['id']]=e['suite']['path']
 elif e.get('type')=='testStart':tests[e['test']['id']]=e['test']
 elif e.get('type')=='testDone':
  t=tests.get(e['testID'],{})
  if suites.get(t.get('suiteID'),'').endswith('/test/v239_card_acceptance_test.dart'):outcomes[t.get('name')]=e.get('result')
rows=[]
for row in json.loads((repo/'qa/tutorial_live/cards/acceptance.json').read_text())['rows']:
 names=[x['name'] for x in row['tests']];assert all(outcomes.get(n)=='success' for n in names),row['card']
 rows.append({'card':row['card'],'atlas':row['atlas'],'cases':names,'current_flutter_TR':'PASS','separate_EN_card_run':'NOT RUN','native_android':'NOT RUN'})
assert len(rows)==24
put('cards/acceptance.json',{'flutter_source_commit':s['flutter_regression_source_commit'],'build_source_commit':s['build_source_commit'],'identical_flutter_inputs':True,'scope':'Actual Flutter BattleV1Screen, fixture transport/defaultTR; not native acceptance.','rows':rows})
write('cards/acceptance.md','# Korunan 24 kart\n\nSon tam Flutter koşusunda identity/atlas/target/duplicate/audio/background ve ayrı timeout/resign vakaları geçti. Widget/fixture kapsamıdır; fiziksel ses, GPU veya Android kabulü değildir. Ayrı EN kart koşusu yeniden çalıştırılmadı.\n\n| Kart | Atlas | Flutter TR | Native Android |\n| --- | --- | --- | --- |\n'+''.join('| '+x['card']+' | '+x['atlas']+' | PASS | NOT RUN |\n' for x in rows)+'\n[Makine matrisi](acceptance.json). Rok/terfi/yakalama, reduced motion ve hızlı cast regresyonları tam koşudadır; bütün kart×özel hamle kombinasyonları denenmedi.\n')
bugs=[
 ('P1','İlk consumable kaydından önceki iade','3fec420','economy','Sahipsiz RTDN ACK edildikten sonra eski PURCHASED yanıtı altın basabiliyordu. Ownership claim kaydından sonra güncel provider kanıtı alınır; consumed durumu da bu yanıttan hesaplanır.','8 vaka: 5 geçti /3 başarısız →8/8; ek gerçek SDK yeni vaka geçti.'),
 ('P1','Eski enqueue tekrarının üçüncü oyuncuyu kilitlemesi','92c71b4','online','Tekrar kullanılan deterministik match ID eski maça çakışınca yeni peer reservation’ı zehirleniyordu. Eski makbuz geri döner; çakışma rollback’i ve completion token ile kendi rezervasyonunu temizler.','6 vaka: 2 geçti /4 başarısız →6/6.'),
 ('P2','İptal edilmiş pending ödeme kilidi','58f3171','economy','Başarılı ve güncel boş ownership yanıtı eski pending durumunu bırakıyordu. Per-product generation yalnız yok olan eski pending’i temizler; yeni stream, açık launch ve başarısız query korunur.','6 vaka: 4 geçti /2 başarısız →6/6.'),
 ('P2','Silinen hesabın puan kimliğinin geri gelmesi','ebd09b2','online','Geç settlement rating projection’ı silinmiş UID/adı yeniden yazıyordu. Mevcut pre/post metadata gate ve cleanup ile silme kazanır; yaşayan peer settlement tamamlanır.','4 vaka: 3 geçti /1 başarısız →4/4.'),
 ('P2','Hesap ayrılırken kabul edilmiş son yerel editin kaybı','017a16d','client','Disk await sırasında değişen departure snapshot eski arşivle kalıyordu. Commit öncesi sınırlı yeniden arşivleme, başarısızlık/churn durumunda eski owner ve canlı editleri korur.','7 vaka: 1 geçti /6 başarısız →7/7.'),
 ('P2','Guest bootstrap’ın yeni oturumu devralması','282edfa','client','createGuestPlayer sonrası yerel await eski akışı yeni owner/generation ile refresh başlatmaya bırakıyordu. Başlangıç owner/generation/state epoch her continuation’da doğrulanır.','6 vaka: 2 geçti /4 başarısız →6/6.'),
 ('P2','Eski savaş seçimine ait komutların uygulanması','a1ab435','battle','Kaydedilmiş Play/Discard/Pass callback’i retarget veya gerçek hamleler sonrasında önceki seçimi uygulayabiliyordu. Sürüm, seçim ve hotseat epoch kabul kapısı eklendi.','Geçerli baseline 7 vaka: 3 geçti /4 başarısız; son 8/8.'),
 ('P2','Silme sonrası V1 davet yazısı','5831476','security','Send daveti yalnız pair lock kullanıyordu. İki hesabı koruyan mevcut withSocialPairMetadata dependency’si ve cleanup uygulanır; ikinci iç lock eklenmez.','12 vaka: 8 geçti /4 başarısız →12/12.'),
 ('P2','Cold Firebase cache ile geçerli davetin reddi','000faaa','runtime','Transaction’ın ilk null cache çağrısında undefined ile abort edilmesi server CAS retry’ını engelliyordu. Null retry’a izin verilir; gerçek boş veride kaydedilmiş hata korunur.','Gerçek SDK 3/4→4/4; repo regression6/8→8/8.'),
]
put('bugs.json',[{'severity':sev,'bug':title,'commit':commit,'area':area,'fix':fix,'proof':proof} for sev,title,commit,area,fix,proof in bugs])
write('BUGS.md','# Dokuz yeni hata\n\n2 P1 + 7 P2. Önceki turlarda kapatılan kusurlar yeniden sayılmadı. Aynı fix’in retry/ownership alt vakaları ayrı bug diye çoğaltılmadı.\n\n| Önem | Kusur | Commit | Kök neden ve düzeltme | Tekrar üretim |\n| --- | --- | --- | --- | --- |\n'+''.join('| '+sev+' | ['+title+'](areas/'+area+'/REPORT.md) | `'+commit+'` | '+fix+' | '+proof+' |\n' for sev,title,commit,area,fix,proof in bugs))
changed=subprocess.check_output(['git','diff','--name-only',s['base_commit'],s['build_source_commit']],cwd=repo,text=True).splitlines()
write('CHANGED-FILES.md','# Değişen dosyalar\n\n'+''.join('- `'+name+'`\n' for name in changed))
put('scope-clean-status.json',{'new_verified_bug_families_found':9,'new_verified_bug_families_fixed':9,'new_verified_source_bug_families_left_open_this_round':0,'scope':'Listed cases and seven source audit areas only; no exhaustive guarantee.','global_bug_free_acceptance':'NOT ESTABLISHED','previous_native_P1':'UNRESOLVED','historical_visual_comparisons':'FAIL','release_decision':'HOLD'})
put('skipped-tests.json',[{'suite':'backend','file':'functions/test/v220-firebase-integration.test.js','reason':'V220_DB_INTEGRATION opt-in disabled. Separate local SDK cases do not relabel this skipped integration as PASS.'}])
gates=[
 ('Dokuz yeni doğrulanmış kaynak hatası','PASS','Hepsi başarısız tekrar üretimden sonra düzeltildi; bu turdan açık doğrulanmış yeni kaynak hatası 0. Evrensel hatasızlık kanıtı değildir.'),
 ('Flutter analiz','PASS','No issues found; final Dart kaynakları değişmedi.'),
 ('Tam Flutter','FAIL',f"{f['counts'].get('success',0)} geçti /{f['counts'].get('error',0)} başarısız /{f['counts'].get('skip',0)} atlandı. 97 eski pixel farkı açık."),
 ('Tam backend','PASS',f"{b['totals']['pass']} geçti /0 başarısız /{b['totals']['skipped']} atlandı; doğrudan gerçek TAP."),
 ('TypeScript ve differential','PASS',f"{ts['totals']['pass']} test; {d['scenarioCount']} senaryo/{d['stateCount']} durum, 0 ayrışma."),
 ('Yerel gerçek RTDB/Admin SDK','PASS','Billing 5/5 ve cold-friendly 4/4. Google/admission/Auth bağımlılıkları ilgili fixture sınırlarında fake; yalnız localhost transport koşulu bellekte değiştirildi.'),
 ('Güncel ARM64 debug APK statik kabulü','PASS','Aynı debug sertifikası, 750 asset, targetSdk 36, ELF/ZIP statik 16 KB. Native runtime kabulü değildir.'),
 ('Önceki Android raster SIGSEGV','FAIL / UNRESOLVED','Yeni sağlıklı Android ortamında kök neden/düzelme kanıtı yok.'),
 ('Yeni native yolculuk / fiziksel FPS-RAM-p95–p99 / gerçek 16 KB','NOT RUN','KVM, donanım GPU ve fiziksel cihaz yok; yeni Android emulator açılmadı.'),
 ('Üretim Firebase / Google / App Check / Integrity','BLOCKED','Staging/üretim kimlikleri ve servis kabulü yok.'),
 ('Play lisans Billing / Console / Pre-launch','BLOCKED','Lisans hesabı, track ve Console erişimi yok; +19 uygunluğu doğrulanmadı.'),
 ('İmzalı release APK/AAB','BLOCKED','Mevcut upload keystore/properties yok; imzalama koruması durdurdu. Kimlik değiştirilmedi.'),
]
put('gates.json',[{'gate':x,'status':y,'reason':z} for x,y,z in gates])
write('GATES.md','# Yayın kararı — RELEASE HOLD\n\n| Kapı | Durum | Somut neden/kapsam |\n| --- | --- | --- |\n'+''.join('| '+x+' | '+y+' | '+z+' |\n' for x,y,z in gates))
copy(repo/'qa/bug_audit_round2/OPEN-ISSUES.md','OPEN-ISSUES.md')
p=q/'OPEN-ISSUES.md';p.write_text(p.read_text().replace('altı yeni hata ailesinden','dokuz yeni hata ailesinden'))
write('APK-SHA256SUMS',a['sha256']+'  '+Path(a['file']).name+'\n')
write('REPORT.md',f'''# Üçüncü sistem taraması

**Bu turda 9 yeni hata doğrulandı ve kapatıldı: 2 P1, 7 P2. Bu turda açık bırakılan doğrulanmış yeni kaynak hatası: 0.** Bütün oyunun hatasız olduğu kanıtlanmadı. **RELEASE HOLD.**

İlk satın alma kaydından önceki iade altın basabiliyor; eski eşleşme isteği üçüncü oyuncuyu kilitleyebiliyordu. Diğer düzeltmeler pending ödeme, silinen puan/davet kaydı, hesap değişimi sırasında kayıt ve bootstrap, eski savaş seçimi ve cold Firebase cache davranışını kapsar. [Dokuz kök neden ve commit](BUGS.md) · [Değişen dosyalar](CHANGED-FILES.md) · [Kapsam sonucu](scope-clean-status.json).

Build kaynağı `{s['build_source_commit']}`. Runtime’ın sabitlendiği ve tam Flutter’ın çalıştığı commit `{s['flutter_regression_source_commit']}`. Sonraki tek test commit’i iki backend testindeki provider çağrı beklentisini ilk registration’daki ikinci doğrulamaya uyarladı; çalışma kodu ve bütün Flutter girdileri byte düzeyinde aynı. Son backend/TS/differential ve APK bu build kaynağıyla doğrulandı. Kaynak dalı, 24 kart, önceki fix’ler, çizimler/atlaslar ve imza kimliği korundu.

| Doğrulama | Sonuç |
| --- | --- |
| Analiz | Hata/uyarı yok |
| Tam Flutter, {f['suites']} dosya | **{f['counts'].get('success',0)} geçti /{f['counts'].get('error',0)} başarısız /{f['counts'].get('skip',0)} atlandı** |
| Tam backend, {b['files']} dosya | {b['totals']['pass']} geçti /0 başarısız /{b['totals']['skipped']} atlandı |
| Tam TypeScript | {ts['totals']['pass']} geçti /0 başarısız /0 atlandı |
| Dart/TS differential | {d['scenarioCount']} senaryo/{d['stateCount']} durum ve tam geçerli hamle kümeleri, 0 ayrışma |
| Yerel Billing SDK | 5/5; yeni unmatched-refund vakası dahil, ayrı SDK bağlantısı kalıcı gold/receipt/event verisini doğruladı |
| Yerel cold-friendly SDK | 4/4; exact source baseline 3/4; bağımsız bağlantı davet silinmesini doğruladı |

Örtüşen koşu sayıları toplanmadı. Node dosyaları doğrudan çalıştırıldı; dosya-wrapper PASS gerçek test kabulü sayılmadı. [Tam Flutter](flutter-summary.json) · [Backend](backend-summary.json) · [TypeScript](typescript-summary.json) · [Atlanan test](skipped-tests.json). [Diferansiyel kaynak/hash kanıtı](evidence/differential/source-provenance.json).

97 Flutter başarısızlığı aynı eski test adları, gerçek pixel hata mesajları ve V239 ile aynı aday PNG baytlarıyla doğrulandı. Golden’lar güncellenmedi; eski farkların tasarım kabulü verilmedi. **Tam Flutter koşusu FAIL.** [Sınıflandırma](evidence/flutter/failure-classification.json) · [Görüntü karşılaştırması](evidence/flutter/golden-comparison.json). [24 kart matrisi](cards/acceptance.md) gerçek Flutter savaş ekranı/fixture kapsamıdır. [TR](screenshots/guided-target-tr.png) ve [EN](screenshots/guided-target-en.png) görüntüleri widget test çıktılarıdır; Android cihaz görüntüsü değildir.

Yeni kural probları 24 kartta private-world noninterference, 4328 malformed-action atomic rejection, codec ve takip edilen perft referanslarını kontrol etti; yeni motor hatası doğrulanmadı. Bu, tam bağımsız oracle değildir. [Sınırlar ve gerçek sayılar](areas/rules/REPORT.md). Ayarlar, ses, hata/legal/native wrapper kaynak incelemesi ve mevcut tam regresyon ek bir doğrulanmış kusur üretmedi; fiziksel/native kabulü değildir.

Yerel SDK’lar gerçek RTDB/Admin SDK transaction’larıdır; Google yanıtları ve ilgili Auth/admission bağımlılıkları fake’tir. Yalnız kesin localhost/demo namespace için standalone transport’taki bir proxy seçimi koşulu bellekte değiştirildi. Proxy ortamı, header’lar ve SDK disk dosyaları korunur. [Billing 5 vaka](billing-sdk-summary.json) · [Cold-friendly 4 vaka](friendly-sdk-summary.json) · [Runtime raporu](areas/runtime/REPORT.md). Bunlar üretim Firebase/App Check/Play kabulü değildir.

İlk backend koşusunda 1420 geçti/17 başarısız/1 atlandı: 15 spawn EPERM ve 2 eski provider-call beklentisi. Başarısız loglar saklandı. Gerekli yerel süreç izniyle son 97 dosya yeniden çalıştırıldı; iki testin exact verify 2 / consume 1, tek grant ve replay’de ek çağrı yok şartları korundu. Paketleme betiğinin dış exit-code aktarımı da düzeltildi; ilk prerequisite failure APK üretmedi ve PASS sayılmadı. [İlk koşu sınıflandırması](evidence/initial-final-attempt/CLASSIFICATION.json).

Güncel ARM64 **debug test APK’sı** üretildi: `com.luno.chess`, `1.6.3+19`, minSdk 24 / targetSdk 36; aynı debug sertifikası, 750 asset ve ELF/ZIP statik 16 KB kontrolleri geçti. [Paket kanıtı](android/apk-verification.json) · [SHA-256](APK-SHA256SUMS). Release APK/AAB mevcut upload key yokluğunda BLOCKED; yeni imza oluşturulmadı.

Önceki API 29 raster SIGSEGV açık. Yeni APK native cihazda oynatılmadı; fiziksel FPS/RAM/p95–p99, uzun maç ve gerçek 16 KB çalışma testi yok. Gerçek Firebase/Google/App Check/Integrity, Play lisanslı ödeme ve Console kabulü tamamlanmadı. [Kapılar](GATES.md) · [Açık sorunlar](OPEN-ISSUES.md). Canlı deploy, gerçek ödeme, Play upload/yayın veya GitHub push yapılmadı. **RELEASE HOLD.**
''')
put('verification.json',{'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':s,'new_verified_bug_families':{'P1':2,'P2':7},'new_verified_open_this_round':0,'global_bug_free_acceptance':'NOT ESTABLISHED','release_decision':'HOLD','real_firebase':'BLOCKED','licensed_billing':'BLOCKED','play_console':'BLOCKED','native_current_apk':'NOT RUN','real_16kb':'NOT RUN','github_push':False,'live_deploy':False,'real_money':False,'play_upload':False})
write('reproduce/README.md','''# Kanıtları yeniden çalıştırma

Betikler kayıtlı worker yollarını kullanır; başka makinede uyarlama gerekir. Pinned Flutter3.47.1/Dart3.13.1/Java21/Node22; `/workspace/toolchains/luno-env.sh` aktivasyonu kullanıldı. Framework yükseltilmedi.

Ham `.log`, `.tap`, `.jsonl`, `.patch` ve `.diff` dosyaları gzip olarak saklanır; kullanmadan önce açın. Bu biçim geçerli patch context baytlarını korur. Alan raporları başarısız fixture/sandbox girişimlerini geçerli ürün tekrar üretiminden ayırır. Gizli başarılı Flutter loader olayları test sayılmaz; başarısızlıklar korunur. Golden referansları değiştirilmez. Yalnız yeni untracked QA çıktıları dış kanıta taşınır; arşivlenen iki generated inventory test öncesi doğrulanmış baytlarına döndürülür.

Node `run_node_direct.py` her dosyada gerçek TAP case sayılarını toplar. Actual SDK için dar in-memory localhost transport koşulu ve dependency fake sınırları alan raporlarında açıkça anlatılır. Değişmemiş tam transport veya üretim servis kabulü iddia edilmez.
''')
# Relative Markdown links to compressed raw evidence remain usable.
for p in q.rglob('*.md'):
 text=p.read_text()
 def fix_link(m):
  target=m[1];candidate=p.parent/target
  return ']('+target+'.gz)' if not candidate.exists() and Path(str(candidate)+'.gz').exists() else m[0]
 p.write_text(re.sub(r'\]\(([^)]+)\)',fix_link,text))
manifest=[]
for p in sorted(q.rglob('*')):
 if p.is_file() and p.name!='EVIDENCE-SHA256SUMS':manifest.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(q).as_posix())
write('EVIDENCE-SHA256SUMS','\n'.join(manifest)+'\n')
print({'qa_files_hashed':len(manifest),'source':s['build_source_commit'],'new_fixed':9,'decision':'HOLD'})
