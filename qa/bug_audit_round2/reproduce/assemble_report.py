from pathlib import Path
import json,gzip,hashlib,re,shutil,subprocess,datetime
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round2');q=repo/'qa/bug_audit_round2'
def read(n):return json.loads((r/n).read_text())
def write(n,s):
 p=q/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def put(n,x):write(n,json.dumps(x,ensure_ascii=False,indent=2)+'\n')
def copy(p,n):
 t=q/n;t.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,t)
def log(p,n):
 s=p.read_text(errors='replace');s=re.sub(r'Bearer\s+[A-Za-z0-9._-]+','Bearer [withheld]',s);s=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[JWT withheld]',s)
 t=q/'logs'/(n+'.gz');t.parent.mkdir(parents=True,exist_ok=True)
 with gzip.open(t,'wt') as f:f.write(s)
assert (r/'pipeline-exit.txt').read_text().strip()=='0'
assert (r/'analyze-final-exit.txt').read_text().strip()=='0'
assert (r/'differential/exit.txt').read_text().strip()=='0'
source=read('source-commit.json');f=read('flutter/summary.json');b=read('full-backend/summary.json');ts=read('full-typescript/summary.json');diff=read('differential/v201a-differential-summary.json');sdk=read('runtime/sdk-proof-final/results.json')
assert b['all_pass'] and ts['all_pass'] and f['done']
assert read('flutter/failure-classification.json')['all_failures_are_existing_pixel_comparisons']
assert sdk['local_sdk_acceptance']=='PASS' and sdk['counts']['pass']==4 and sdk['counts']['fail']==0
apk=read('android/Luno-Chess-bug-audit-round2-debug-arm64/verification.json')
assert hashlib.sha256(Path(apk['file']).read_bytes()).hexdigest()==apk['sha256']
assert apk['source_asset_files_verified']==750
for n,x in [('source.json',source),('flutter-summary.json',f),('backend-summary.json',b),('typescript-summary.json',ts),('differential-summary.json',diff),('sdk-final-summary.json',sdk)]:put(n,x)
copy(r/'android/Luno-Chess-bug-audit-round2-debug-arm64/verification.json','android/apk-verification.json')
for name in ['baseline.json','analyze-preflight-exit.txt','flutter/failure-classification.json','flutter/golden-comparison.json','flutter/suite-outcomes.json','android/release-status.json','android/runtime-provenance.json','android/commands.json','android/disk-recovery.json','android/post-build-space-recovery.json','differential/source-provenance.json']:
 copy(r/name,'evidence/'+name)
for area in ['security','economy','online','client','rules','runtime']:
 p=r/area;assert (p/'REPORT.md').exists(),area
 for fpath in p.rglob('*'):
  if not fpath.is_file():continue
  rel=fpath.relative_to(p).as_posix()
  if fpath.name in {'fixed-index.cjs','baseline-index.cjs','fixed-index.js','candidate-index.cjs'}:continue
  if fpath.suffix=='.log':
   log(fpath,area+'-'+rel.replace('/','-'))
   target=q/'areas'/area/(rel+'.gz');target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(q/'logs'/(area+'-'+rel.replace('/','-')+'.gz'),target)
  elif fpath.suffix in {'.json','.md','.patch','.py','.cjs','.dart','.txt','.sh'}:copy(fpath,'areas/'+area+'/'+rel)
for p in r.glob('*.log'):log(p,p.name)
for area in ['full-backend','full-typescript','differential','android']:
 for p in (r/area).rglob('*.log'):log(p,p.relative_to(r).as_posix().replace('/','-'))
for name in ['full.jsonl','full-stderr.log']:log(r/'flutter'/name,'flutter-'+name)
for name in ['run_node_direct.py','summarize.py','post_tests.py','run_flutter_final.sh','android/build_android.py','android/audit_apk.py']:copy(r/name,'reproduce/'+name)
for language in ['tr','en']:
 p=r/'generated/luno_chess/qa/v230/screens'/('guided-target-'+language+'.png')
 if p.exists():copy(p,'screenshots/current-battle-target-'+language+'.png')
put('scope-clean-status.json',{'new_verified_bug_families_found':6,'new_verified_bug_families_fixed':6,'new_verified_source_bug_families_left_open_this_round':0,'scope':'Six audited areas and explicitly listed adversarial cases; not an exhaustive bug-free guarantee.','previous_native_P1':'UNRESOLVED','historical_visual_comparisons':'FAIL','global_bug_free_acceptance':'NOT ESTABLISHED','release_decision':'HOLD'})
put('skipped-tests.json',[{'suite':'backend','test':'V220 actual isolated RTDB integration (Auth, App Check and Play remain mocked)','file':'functions/test/v220-firebase-integration.test.js','reason':'V220_DB_INTEGRATION opt-in not enabled in the unit run; separate four-case local SDK proof does not turn this skipped test into a PASS.'}])
bugs=[
 ('P1','Owned inactive subscription restore','162dfbb','Güncel ON_HOLD/EXPIRED Google kararı eski claim/profile hakkına uygulanmıyordu. Owner/product doğrulaması, claim CAS ve profile projection ile sadece owned token güncellenir; diğer aktif token ve yeni renewal korunur.','economy'),
 ('P2','Billing snapshot sırası','ca16acf','Eski restore, yeni verification snapshot’ını ezip ikinci üyelik launch’ını açabiliyordu. Revision/observedAt ve legacy fallback sırası korunur; session reset ve bozuk metadata denetlenir.','client'),
 ('P2','Covered Friendly route','3df9d16','Geç join yanıtı ilgisiz üst route’u replace ediyordu. Match pending tutulur; owner route current/resumed olunca bir kez açılır; account/dispose eski callback’i keser.','client'),
 ('P2','Silme sonrası V1 admission','3936314','HTTP403 eski queue/room private metadata’sını temizlemiyordu. Existing account-metadata pre/post gate ve leaveAccount cleanup iki canonical admission route’a uygulanır.','online'),
 ('P2','DM moderation membership','dbbfbc2','Legacy conversation-key collision başka pair’in mesajını moderation’a kopyalayabiliyordu. Declared exact pair kontrolü yalnız bounded members + seçilmiş message read ile yapılır; eski members-absent contract korunur.','security'),
 ('P2','Authored notification erasure','9d41c50','Push-ID ve reddedilmiş/orphan ilişki notices’ında silinen UID/alias kalıyordu. Bounded recipient pagination, owner-aware removal, retry checkpoint ve ayrı bounded private resume limiter eklenir; Authfailure counter’ı finalcleanup’a kadar saklanır.','security'),
]
put('bugs.json',[{'severity':a,'bug':b,'commit':c,'fix':d,'area':e} for a,b,c,d,e in bugs])
write('BUGS.md','# İkinci turda kapatılan altı yeni kusur\n\n1 P1 + 5 P2. Önceki yedi düzeltme yeniden sayılmadı. Aynı fix içindeki retry/ownership alt senaryoları ayrı bug diye şişirilmedi.\n\n| Önem | Hata | Commit | Kök neden / düzeltme | Kanıt |\n| --- | --- | --- | --- | --- |\n'+''.join('| '+a+' | '+b+' | `'+c+'` | '+d+' | [Alan raporu](areas/'+e+'/REPORT.md) |\n' for a,b,c,d,e in bugs)+'\nHer hata için başarısız tekrar üretim ve sonra geçen regresyon kaydedildi. Online ajanının dört ek test yazma/çalıştırma çağrısı otomatik incelemede kullanım limitinde reddedildi ve çalışmadı. Root daha dar mevcut altı vakayı kaynak mutasyonu/izin yükseltmesi olmadan 6/6 doğruladı; yazılmayan dört test PASS sayılmadı.\n')
files=subprocess.check_output(['git','diff','--name-only',source['base_commit'],source['build_source_commit']],cwd=repo,text=True).splitlines()
write('CHANGED-FILES.md','# Değişen kaynak ve yeni regresyonlar\n\n`'+source['base_commit']+'` → `'+source['build_source_commit']+'`\n\n'+''.join('- `'+x+'`\n' for x in files))
write('APK-SHA256SUMS',apk['sha256']+'  '+Path(apk['file']).name+'\n')
# Require each current card acceptance result rather than infer it from totals.
tests={};suites={};outcomes={}
for line in (r/'flutter/full.jsonl').open():
 try:event=json.loads(line)
 except json.JSONDecodeError:continue
 if event.get('type')=='suite':suites[event['suite']['id']]=event['suite']['path']
 elif event.get('type')=='testStart':tests[event['test']['id']]=event['test']
 elif event.get('type')=='testDone':
  t=tests.get(event['testID'],{});path=suites.get(t.get('suiteID'),'')
  if path.endswith('/test/v239_card_acceptance_test.dart'):outcomes[t.get('name')]=event.get('result')
old=json.loads((repo/'qa/tutorial_live/cards/acceptance.json').read_text());rows=[]
for x in old['rows']:
 names=[v['name'] for v in x['tests']];assert all(outcomes.get(n)=='success' for n in names),x['card']
 rows.append({'card':x['card'],'atlas':x['atlas'],'current_tr_flutter':'PASS','cases':names,'new_separate_en_run':'NOT RUN','native_android':'NOT RUN'})
assert len(rows)==24
put('cards/acceptance.json',{'source_commit':source['build_source_commit'],'scope':'Completed full Flutter BattleV1Screen tests, fixture transport/defaultTR; not native acceptance.','rows':rows})
write('cards/acceptance.md','# Korunan 24 kart — son kaynak Flutter kabulü\n\nDoğru identity/atlas/target/duplicate/audio/background ve ayrı timeout/resign testleri her kartta geçti. Transport fixture; fiziksel ses/GPU veya Android kabulü değildir. Ayrı EN kart koşusu bu tur yeniden çalıştırılmadı.\n\n| Kart | Atlas | Son TR Flutter | Native Android |\n| --- | --- | --- | --- |\n'+''.join('| '+x['card']+' | '+x['atlas']+' | PASS | NOT RUN |\n' for x in rows)+'\n[Makine matrisi](acceptance.json). Rok/terfi/yakalanma, reduced motion ve hızlı cast regresyonları tam koşudadır; tüm kart×özelhamle kombinasyonları denenmedi.\n')
gates=[
 ('Bu tur doğrulanan altı kaynak kusuru','PASS','Hepsi failing repro sonrası düzeltildi; final hedefli incelemede bu turdan açık doğrulanmış yeni kusur0. Evrensel bug-free iddiası değildir.'),
 ('Tam backend','PASS',f"{b['totals']['pass']} pass /{b['totals']['fail']} fail /{b['totals']['skipped']} skip; doğrudan Node gerçek TAP."),
 ('Tam TypeScript ve differential','PASS',f"{ts['totals']['pass']} pass; {diff['scenarioCount']} senaryo /{diff['stateCount']} state+legal set, sıfır ayrışma."),
 ('Gerçek yerel SDK Billing','PASS','Dört dar vaka; ayrı SDK durability, Google fake, tek in-memory loopback proxy condition. Repo/SDK disk ve env/header bağları değişmedi.'),
 ('Tam Flutter','FAIL',f"{f['counts'].get('success',0)} pass /{f['counts'].get('error',0)} fail /{f['counts'].get('skip',0)} skip; eski 97 pixel farkı açık."),
 ('Güncel ARM64 debug APK statik kabulü','PASS','Aynı debug imzası / 750 asset / targetSdk 36 / ELF+ZIP 16 KB; gerçek runtime 16 KB değildir.'),
 ('Önceki Android raster SIGSEGV','FAIL / UNRESOLVED','Sağlıklı gerçek Android’de kök neden/düzeltme kanıtı yok; bu tur emulator/cihaz testi yapılmadı.'),
 ('Fiziksel Android/E2E/FPS/RAM/p95–p99/16KB','NOT RUN','KVM/GPU/fiziksel cihaz yok; widget görüntüleri cihaz performansı değildir.'),
 ('Gerçek Firebase/Google/AppCheck/Integrity','BLOCKED','Üretim/staging kimliği ve servis kabulü yok; local SDK proof bunların yerine geçmez.'),
 ('Play lisans Billing ve Console beyanları/Pre-launch','BLOCKED','Lisans hesabı/track/Play Services/Console geçmişi yok; +19 kullanılabilirliği bilinmiyor.'),
 ('Release APK/AAB','BLOCKED','Mevcut upload key/properties yok; signing guard durdu, imza kimliği değiştirilmedi.'),
]
put('gates.json',[{'gate':x,'status':y,'reason':z} for x,y,z in gates])
write('GATES.md','# Genel yayın kararı — RELEASE HOLD\n\n| Kapı | Durum | Kapsam / somut engel |\n| --- | --- | --- |\n'+''.join('| '+x+' | '+y+' | '+z+' |\n' for x,y,z in gates))
write('REPORT.md',f'''# İkinci sistem taraması

**6 yeni hata bulundu ve düzeltildi: 1 P1, 5 P2. Bu turda doğrulanıp açık bırakılan yeni kaynak hatası: 0.** Bu sonuç bütün oyunun hatasız olduğunu kanıtlamaz. Eski Android çökmesi ve 97 görsel karşılaştırma farkı açık; gerçek cihaz ve servis kabulü tamamlanmadı. **RELEASE HOLD.**

Build ve son regresyon kaynağı: `{source['build_source_commit']}`. Başlangıç: `{source['base_commit']}`. Düzeltmeler ayrı commit’lerde tutuldu. Son QA commit’i çalışma kodunu değiştirmez. Oyun kuralları, 24 kart, önceki düzeltmeler, çizimler, atlaslar ve imzalama kimliği korundu.

[Kök nedenler ve commit’ler](BUGS.md) · [Değişen dosyalar](CHANGED-FILES.md) · [Kapsam sonucu](scope-clean-status.json) · [Açık sorunlar](OPEN-ISSUES.md).

| Son kaynakta doğrulama | Sonuç |
| --- | --- |
| Flutter analiz | Hata ve uyarı yok |
| Tam Flutter, {f['suites']} dosya | **{f['counts'].get('success',0)} geçti / {f['counts'].get('error',0)} başarısız / {f['counts'].get('skip',0)} atlandı** |
| Tam backend | {b['totals']['pass']} geçti / {b['totals']['fail']} başarısız / {b['totals']['skipped']} atlandı |
| Tam TypeScript, Dart bridge etkin | {ts['totals']['pass']} geçti / {ts['totals']['fail']} başarısız / {ts['totals']['skipped']} atlandı |
| Dart/TypeScript differential | {diff['scenarioCount']} senaryo, {diff['stateCount']} durum ve tam geçerli hamle kümeleri; 0 ayrışma |
| Gerçek yerel RTDB/Admin SDK | 4/4 geçti; bağımsız SDK bağlantısı kalıcı veriyi doğruladı |

Koşular örtüşür; sayıları toplanmadı. Node dosyaları ayrı süreçlerde, gerçek TAP vaka sayılarıyla çalıştırıldı. Flutter’daki gizli başarılı yükleyici olayları test sayısına eklenmedi; tüm başarısızlıklar korundu. [Flutter](flutter-summary.json) · [Backend](backend-summary.json) · [TypeScript](typescript-summary.json) · [Atlanan test](skipped-tests.json).

97 başarısızlığın tamamında eski test adı ve gerçek pixel hata mesajı doğrulandı. Her aday PNG eski V239 adayıyla byte düzeyinde aynıydı. Golden görüntüleri güncellenmedi; bu eşitlik eski farkların tasarım kabulü değildir. **Tam Flutter koşusu başarısızdır.** [Sınıflandırma](evidence/flutter/failure-classification.json) · [Görüntü hash karşılaştırması](evidence/flutter/golden-comparison.json).

[24 kart kabul matrisi](cards/acceptance.md), gerçek Flutter savaş ekranında fixture transport ile geçen testlerden üretildi. Native Android kabulü değildir. Bu koşuda üretilen [TR](screenshots/current-battle-target-tr.png) ve [EN](screenshots/current-battle-target-en.png) görüntüleri widget test çıktılarıdır. Fiziksel cihaz görüntüsü veya performans ölçümü olarak sunulmadı. Kural motoruna yeni bir tam bağımsız test oracle’ı uydurulmadı; simetri ve muhasebe kontrollerinin sınırları [alan raporunda](areas/rules/REPORT.md) açıklandı. Differential için değişmeyen AOT girdileri [exact hash ile doğrulandı](evidence/differential/source-provenance.json).

Yerel SDK kabulündeki önceki timeout’un test düzeneği nedeni bulundu: Admin SDK dış faye constructor’ını kullanmıyor; standalone bundle kendi transport’unu içeriyor. Yalnız kesin localhost demo adresi için bir proxy seçimi koşulu bellekte değiştirildi. Transaction uygulaması, ortam değişkenleri, header’lar ve SDK disk dosyaları korundu. İlk üç eski vaka ile son kaynaktaki dört vaka ayrı kaydedildi; geçmiş timeout’lar başarı diye yeniden yazılmadı. Son koşu, RTDN gelmeden owned inactive subscription’ın hakkı kaldırmasını da doğruladı. Google Play yanıtları sahtedir; bu test Auth, App Check veya üretim Firebase/Play kabulü değildir. [Ayrıntılar](areas/runtime/REPORT.md) · [Son SDK sonuçları](sdk-final-summary.json).

Güncel **ARM64 debug test APK’sı** bu kaynak commit’inden üretildi: `com.luno.chess`, `1.6.3+19`, minSdk 24, targetSdk 36. Aynı debug sertifikası, kaynakla aynı 750 asset ve native ELF/ZIP statik 16 KB kontrolleri doğrulandı. Runtime payload hash’i önceki APK’dan farklıdır. [Paket kanıtı](android/apk-verification.json) · [SHA-256](APK-SHA256SUMS). Upload anahtarı bulunmadığı için release APK/AAB üretimi BLOCKED; imza kimliği değiştirilmedi.

Yeni APK native cihazda oynatılmadı. Önceki API 29 raster SIGSEGV için kök neden ve düzelme kanıtı yok. Fiziksel FPS, RAM, build/raster p95–p99, uzun maç ve gerçek 16 KB runtime testleri yapılmadı. Üretim Firebase, Google giriş, App Check, Play Integrity, lisanslı ödeme ve Play Console kabulü eksik. [Kabul kapıları](GATES.md). Canlı deploy, gerçek ödeme, Play upload/yayın ve GitHub push yapılmadı. **RELEASE HOLD.**
''')
write('OPEN-ISSUES.md','''# Yayını engelleyen açık sorunlar

| Öncelik / kapı | Somut neden | Durum |
| --- | --- | --- |
| P1 — önceki native raster çökmesi | API 29 profil açılışında `1.raster` / `libflutter.so` / allocator SIGSEGV kaydı var. Sonraki welcome görüntüleri kök neden veya düzelme kanıtı değildir. Bu tur yeni native tekrar yapılmadı. | OPEN / UNRESOLVED |
| Görsel kabul | 97 test referans görüntüsünden farklı. Yeni adaylar eski V239 adaylarıyla aynı; golden referansları incelenip onaylanarak değiştirilmedi. Bu durum yeni üretim hatası diye yeniden sayılmadı; suite başarısız kalır. | FAIL |
| Gerçek Android yolculuğu ve performans | Bu worker’da KVM, donanım GPU veya fiziksel cihaz yok. Yeni APK ile tutorial→maç→online→ödül zinciri, uzun maç, FPS/p95–p99/RAM ve gerçek 16 KB çalışma testi tamamlanmadı. | NOT RUN |
| Güvenlik ve backend servis kabulü | Kaynak ve yerel testler geçti; staging/üretim Auth, App Check, Integrity ve Google hesap kabulü için erişim yok. | BLOCKED |
| Play Billing | Gerçek lisans test hesabı ve Play track yok; pending, restore, iptal, refund ve üyelik senaryoları gerçek Play’de doğrulanmadı. | BLOCKED |
| İmzalı release APK/AAB | Mevcut upload keystore/properties bulunmuyor. Koruma doğru biçimde build’i engelliyor. Yeni anahtar oluşturulmadı. | BLOCKED |
| Play Console | +19’un geçmişte kullanılabilirliği, mağaza beyanları/görselleri, Data Safety, gizlilik ve silme bağlantıları, içerik derecelendirmesi, test hesabı, Pre-launch Report ve kapalı test koşulları doğrulanmadı. | BLOCKED |

Bu tur düzeltmesi yapılan altı yeni hata ailesinden açık bırakılan yok. Bu sınırlı sonuç yukarıdaki engelleri kapatmaz. Genel karar **RELEASE HOLD**.
''')
put('verification.json',{'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':source,'new_verified_bug_families':{'P1':1,'P2':5},'open_new_verified_source_bugs_this_round':0,'global_bug_free_acceptance':'NOT ESTABLISHED','historical_native_P1':'OPEN','historical_golden':'FAIL','release_decision':'HOLD','current_native_apk':'NOT RUN','physical_perf':'NOT RUN','real_16kb':'NOT RUN','production_firebase':'BLOCKED','licensed_billing':'BLOCKED','play_console':'BLOCKED','live_deploy':False,'real_money':False,'play_upload':False,'github_push':False})
manifest=[]
for p in sorted(q.rglob('*')):
 if p.is_file() and p.name!='EVIDENCE-SHA256SUMS':manifest.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(q).as_posix())
write('EVIDENCE-SHA256SUMS','\n'.join(manifest)+'\n');print({'qa_files_hashed':len(manifest),'source':source['build_source_commit'],'release':'HOLD'})
