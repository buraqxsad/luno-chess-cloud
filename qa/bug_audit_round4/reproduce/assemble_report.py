from pathlib import Path
import json,hashlib,gzip,shutil,re,subprocess,datetime
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round4');q=repo/'qa/bug_audit_round4'
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
s=data('source-commit.json');f=data('flutter/summary.json');b=data('full-backend/summary.json');ts=data('full-typescript/summary.json');d=data('differential/v201a-differential-summary.json');sdk=data('runtime-billing/results.json')
assert b['all_pass'] and ts['all_pass'] and f['done']
assert data('flutter/failure-classification.json')['all_failures_are_existing_pixel_comparisons']
assert sdk['local_sdk_acceptance']=='PASS' and sdk['counts']['pass']==7 and sdk['counts']['fail']==0
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==s['build_source_commit']
assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo).strip()
assert not subprocess.check_output(['git','diff',s['flutter_regression_source_commit'],s['build_source_commit'],'--','luno_chess','functions/index.js','functions/lib'],cwd=repo).strip()
a=data('android/Luno-Chess-bug-audit-round4-debug-arm64/verification.json')
assert hashlib.file_digest(Path(a['file']).open('rb'),'sha256').hexdigest()==a['sha256'] and a['source_asset_files_verified']==750
assert data('android/release-status.json')['release_aab']=='BLOCKED'
for name,obj in [('source.json',s),('flutter-summary.json',f),('backend-summary.json',b),('typescript-summary.json',ts),('differential-summary.json',d),('billing-sdk-summary.json',sdk)]:put(name,obj)
copy(r/'android/Luno-Chess-bug-audit-round4-debug-arm64/verification.json','android/apk-verification.json')
for name in ['baseline.json','flutter/failure-classification.json','flutter/golden-comparison.json','flutter/suite-outcomes.json','android/release-status.json','android/runtime-provenance.json','android/commands.json','android/disk-recovery.json','android/prebuild-cache-recovery.json','android/package-audit-recovery.json','android/initial-package-audit/commands.json','android/post-build-space-recovery.json','differential/source-provenance.json','approved-visual-candidates.json','backend-scope-provenance.json','initial-analyze/CLASSIFICATION.json']:
 copy(r/name,'evidence/'+name)
for area in ['economy','online','client','battle','rules','visual','runtime-billing']:
 for p in (r/area).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r/area).as_posix();target='areas/'+area+'/'+rel
  if p.name in {'fixed-index.cjs','baseline-index.cjs','canonical-baseline-index.cjs','candidate-index.cjs'}:continue
  if p.suffix in {'.log','.tap','.jsonl','.patch','.diff'}:compressed(p,target)
  elif p.name=='SHA256SUMS' or p.suffix in {'.json','.md','.py','.cjs','.dart','.ts','.txt','.sh','.png','.js','.gz'}:copy(p,target)
for name in ['full-backend','full-typescript','differential','flutter','android','initial-analyze']:
 for p in (r/name).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r).as_posix()
  if p.suffix in {'.log','.tap','.jsonl'}:compressed(p,'logs/'+rel)
  elif name=='initial-analyze' and p.suffix in {'.json','.txt'}:copy(p,'evidence/'+rel)
for p in r.glob('*.log'):compressed(p,'logs/'+p.name)
for name in ['run_node_direct.py','summarize.py','post_tests.py','run_flutter_final.sh','finish_pipeline.sh','run_backend_final.sh','android/build_android.py','android/audit_apk.py','android/resume_verified_apk.py','assemble_report.py','prepare_final_billing_sdk.py']:copy(r/name,'reproduce/'+name)
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
 ('P1','RTDN lease’in ACK ve takeover sahipliği','4c0e823','economy','Yarım kalan processing lease başarı diye ACK ediliyor, eski worker yeni sahibin durumunu ezebiliyordu. Yalnız complete duplicate kabul edilir; her attempt UUID ile complete/failed CAS yapar.','8 baseline vakası: 4 geçti / 4 başarısız →8/8; ilgili 84/84.',True),
 ('P2','Kurtarma yazısının kalıcı sanılması','e1bdd77','client','SharedPreferences reddedilen yazıyı cache’inde tutuyordu. Ack almamış kurtarma ve kalıcı pending intent yeniden denenir; restart, UID değişimi ve erasure korunur.','35 baseline vakası: 15 geçti / 20 başarısız; son 49 yeni + 70 eski = 119/119.',True),
 ('P2','Eski private projection’dan pencere açılması','7723784','battle','Eski frame’in knowledge/deck widget’ı yeni sürüm diye damgalanıyordu. Pencere açılışı origin stateVersion ile kabul edilir.','7 birleşik baseline vakası: 4 geçti / 3 başarısız; iki overlay hatası ve bir compact residual; son 7/7, ilgili 122/122.',True),
 ('P2','Türkçe arena başlığında eksik glifler','fc336b7','visual','Cinzel-latin ve inherited Spectral-latin İ/Ş/Ğ içermiyordu. Mevcut CinzelTurkish fallback açıkça tanımlandı.','3 raster vakası: 1 geçti / 2 başarısız → 3/3; ilgili 39/39. Tam PNG değişimi yalnız başlıkta 2045 piksel.',True),
 ('P1','Önceki aile: oda/davet ve eski rezervasyon kapsamı','0662662 +21a15c3','online','Queue koruması oda/daveti kapsamıyordu. Yeni lease nonce’si; legacy fallback/persisted ID; eski çakışmış rezervasyonun koşullu CAS ile emekliye ayrılması.','13 baseline vakası: 5 geçti / 8 başarısız; son 13/13 ve ilgili 62/62.',False),
 ('P2','Önceki aile: compact Pass yolu','7723784','battle','Küçük ekran/büyük yazı ikon kontrolü önceki selection gate’i kullanmıyordu. Aynı mevcut kapı bu yola da uygulandı.','Bir failing stale-pass + geçerli current control; yukarıdaki birleşik 7 ve 122 koşusunda geçti.',False),
]
put('bugs.json',[{'severity':sev,'bug':title,'commit':commit,'area':area,'fix':fix,'proof':proof,'new_independent_family':new} for sev,title,commit,area,fix,proof,new in bugs])
write('BUGS.md','# Altı somut kusur — dört yeni aile, iki kapsam eksiği\n\nYeni aileler: 1 P1 + 3 P2. Önceki ailelerdeki oda/davet/legacy ve compact kontrol eksikleri: 1 P1 + 1 P2. Toplam 6 somut düzeltme; önceki aileler yeni diye yeniden sayılmadı. Aynı fix’in retry/owner alt vakaları ayrı bug yapılmadı.\n\n| Önem | Kusur | Tür | Commit | Kök neden/düzeltme | Kanıt |\n| --- | --- | --- | --- | --- | --- |\n'+''.join('| '+sev+' | ['+title+'](areas/'+area+('/PROMOTION-FIX.md' if area=='visual' else '/REPORT.md')+') | '+('Yeni aile' if new else 'Önceki ailede kapsam eksiği')+' | `'+commit+'` | '+fix+' | '+proof+' |\n' for sev,title,commit,area,fix,proof,new in bugs))
changed=subprocess.check_output(['git','diff','--name-only',s['base_commit'],s['build_source_commit']],cwd=repo,text=True).splitlines()
write('CHANGED-FILES.md','# Değişen dosyalar\n\n'+''.join('- `'+name+'`\n' for name in changed))
put('scope-clean-status.json',{'new_independent_families_found':4,'new_independent_families_fixed':4,'prior_family_residuals_fixed':2,'concrete_defects_fixed':6,'new_verified_source_defects_left_open_this_round':0,'scope':'Listed proofs and bounded source audits only; no exhaustive guarantee.','global_bug_free_acceptance':'NOT ESTABLISHED','previous_native_P1':'UNRESOLVED','historical_visual_comparisons':'FAIL','release_decision':'HOLD'})
put('skipped-tests.json',[{'suite':'backend','file':'functions/test/v220-firebase-integration.test.js','reason':'V220_DB_INTEGRATION opt-in disabled. Separate local SDK cases do not relabel this skipped integration as PASS.'}])
gates=[
 ('Altı somut kaynak düzeltmesi','PASS','Dört yeni aile ve önceki iki kapsam eksiği başarısız tekrar üretim sonrası kapatıldı. Evrensel hatasızlık kanıtı değildir.'),
 ('Flutter analiz','PASS','No issues found; ilk redundant null warning düzeltildi, test başlamadan tekrar analiz edildi.'),
 ('Tam Flutter','FAIL',f"{f['counts'].get('success',0)} geçti /{f['counts'].get('error',0)} başarısız /{f['counts'].get('skip',0)} atlandı. 97 eski golden farkı açık."),
 ('Tam backend','PASS',f"{b['totals']['pass']} geçti /0 başarısız /{b['totals']['skipped']} atlandı; gerçek per-case TAP."),
 ('TypeScript/differential','PASS',f"{ts['totals']['pass']} test; {d['scenarioCount']} senaryo/{d['stateCount']} durum ve tam legal set, sıfır ayrışma."),
 ('Yerel gerçek RTDB/Admin SDK','PASS','Yedi dar vaka: altı Billing/lease ve bir legacy V1 recovery. Google fake, production/Auth/Play kabulü değildir.'),
 ('Güncel ARM64 debug APK statik kabulü','PASS','Aynı sertifika, 750 asset, targetSdk 36, ELF/ZIP statik 16 KB; native runtime kabulü değildir.'),
 ('Önceki Android raster SIGSEGV','FAIL','Yeni sağlıklı native ortamda kök neden/düzelme kanıtı yok.'),
 ('Native yolculuk/fiziksel FPS-RAM-p95–p99/gerçek 16 KB','NOT RUN','KVM/GPU/fiziksel Android yok; emulator açılmadı.'),
 ('Üretim Firebase/Google/App Check/Integrity','BLOCKED','Staging/üretim erişimi ve gerçek servis kabulü yok.'),
 ('Play lisans Billing/Console/Pre-launch','BLOCKED','Lisans hesabı/track/Console erişimi yok; +19 uygunluğu bilinmiyor.'),
 ('Release APK/AAB','BLOCKED','Mevcut upload key/properties yok; imza değiştirilmedi.'),
]
put('gates.json',[{'gate':x,'status':y,'reason':z} for x,y,z in gates])
write('GATES.md','# RELEASE HOLD\n\n| Kapı | Durum | Kapsam/somut neden |\n| --- | --- | --- |\n'+''.join('| '+x+' | '+y+' | '+z+' |\n' for x,y,z in gates))
write('OPEN-ISSUES.md','# Yayını engelleyen açık sorunlar\n\n| Öncelik / kapı | Somut neden | Durum |\n| --- | --- | --- |\n| P1 — önceki native raster çökmesi | API 29 profil açılışında raster/libflutter.so/allocator SIGSEGV kaydı var. Bu tur sağlıklı native ortamda tekrar üretim veya kök nedenin kapandığına dair kanıt yok. | OPEN / UNRESOLVED |\n| Görsel kabul | 97 referans karşılaştırması başarısız. Bütün çiftler incelendi; 96 aday V239 ile aynı, yalnız promotion başlığının kanıtlanmış Türkçe font düzeltmesi değişti. Eski render/font ortamı ve bazı tasarım onayları eksik. Golden değiştirilmedi. | FAIL |\n| Gerçek Android yolculuğu ve performans | KVM, donanım GPU veya fiziksel cihaz yok. Yeni APK ile tutorial→maç→online→ödül zinciri, uzun maç, FPS/build-raster p95–p99/RAM ve gerçek 16 KB çalışma testi yapılmadı. | NOT RUN |\n| Güvenlik ve backend servis kabulü | Kaynak, sahte bağımlılıklı regresyon ve dar yerel SDK kontrolleri geçti. Staging/üretim Auth, App Check, Integrity ve gerçek Google hesap kabulü için erişim yok. | BLOCKED |\n| Play Billing | Lisans test hesabı ve Play track yok. Pending, restore, iptal, refund ve üyelik gerçek Play üzerinde doğrulanmadı. | BLOCKED |\n| İmzalı release APK/AAB | Mevcut upload keystore/properties yok; imzalama koruması derlemeyi durduruyor. Yeni anahtar oluşturulmadı. | BLOCKED |\n| Play Console | +19 uygunluğu; mağaza metin/görselleri, Data Safety, gizlilik ve hesap silme bağlantıları, içerik derecelendirmesi, test hesabı, Pre-launch Report ve kapalı test koşulları doğrulanmadı. | BLOCKED |\n\nBu turdaki 4 yeni aile ve önceki düzeltmelerdeki 2 kapsam eksiği kapatıldı. Bu sınırlı sonuç yukarıdaki engelleri kapatmaz. Genel karar **RELEASE HOLD**.\n')
write('APK-SHA256SUMS',a['sha256']+'  '+Path(a['file']).name+'\n')
write('REPORT.md',f'''# Dördüncü sistem taraması

**4 yeni hata ailesi ve önceki düzeltmelerin kapsamadığı 2 yol kapatıldı: toplam 6 somut kusur.** Yeni aileler 1 P1/3 P2, önceki ailelerdeki eksikler 1 P1/1 P2. Bu turda doğrulanıp açık bırakılan yeni kaynak kusuru: 0. Bütün oyunda hatasızlık kanıtlanmadı. **RELEASE HOLD.**

Yarım RTDN bildiriminin kaybolması ve eski worker’ın takeover durumunu ezmesi; kalıcı sanılan recovery yazıları; eski private projection’dan pencere açılması; Türkçe arena başlığında eksik glifler düzeltildi. Oda/davet/legacy rezervasyonları ve compact Pass, önceki ailelerin eksik yolları olarak ayrıca kapatıldı. [Altı kök neden/commit](BUGS.md) · [Dosyalar](CHANGED-FILES.md) · [Kapsam sonucu](scope-clean-status.json).

Build ve son Flutter kaynağı `{s['build_source_commit']}`. Backend koşusu `{s['backend_regression_source_commit']}` ile başladı; sonradan yalnız GameStore’daki redundant null guard kaldırıldı. Backend, TypeScript ve Dart motor/runner girdileri final kaynakla byte-identical; [hash/provenance](evidence/backend-scope-provenance.json). Tam Flutter final kaynakta yeniden çalıştı. Önceki düzeltmeler, 24 kart, oyun kuralları, sanat/atlaslar ve imza kimliği korundu.

| Doğrulama | Sonuç |
| --- | --- |
| Analiz | Hata/uyarı yok |
| Tam Flutter, {f['suites']} dosya | **{f['counts'].get('success',0)} geçti /{f['counts'].get('error',0)} başarısız /{f['counts'].get('skip',0)} atlandı** |
| Tam backend, {b['files']} dosya | {b['totals']['pass']} geçti /0 başarısız /{b['totals']['skipped']} atlandı |
| Tam TypeScript | {ts['totals']['pass']} geçti /0 başarısız /0 atlandı |
| Dart/TS differential | {d['scenarioCount']} senaryo / {d['stateCount']} durum ve tam geçerli hamle kümeleri; 0 ayrışma |
| Yerel gerçek RTDB/Admin SDK | 7/7: Billing/lease 6 + legacy recovery 1; bağımsız SDK kalıcı veriyi doğruladı |

Koşular örtüşür, sayıları toplanmadı. Node dosyaları doğrudan gerçek TAP vakalarıyla çalıştırıldı. [Flutter](flutter-summary.json) · [Backend](backend-summary.json) · [TS](typescript-summary.json) · [Atlanan opt-in test](skipped-tests.json). [Diferansiyel kaynak kanıtı](evidence/differential/source-provenance.json).

97 görsel FAIL’ın tamamı ayrıca görsel olarak incelendi; eski render/font ortamı ve eksik tasarım onayı genel kabulü engelliyor. 96 aday V239 ile aynı baytlar; promotion adayı kanıtlanmış Türkçe font düzeltmesi nedeniyle değişti. Önceki üçüncü tur adayı ile fark yalnız (99,91)–(291,126) başlık bölgesinde 2045 piksel. Önce/sonra raster ve tam ekranlar ayrıca incelendi; paketleme yalnız bu exact PNG hash’ini tanır. **Hiçbir golden güncellenmedi; tam Flutter FAIL.** [97-case inceleme](areas/visual/MATRIX.md) · [Glif düzeltmesi](areas/visual/PROMOTION-FIX.md) · [Onaylanan tek aday hash](evidence/approved-visual-candidates.json) · [Son karşılaştırma](evidence/flutter/golden-comparison.json).

[24 kart matrisi](cards/acceptance.md) gerçek Flutter savaş ekranı/fixture kapsamıdır; native Android değildir. [TR](screenshots/guided-target-tr.png) ve [EN](screenshots/guided-target-en.png) widget çıktılarıdır. Yeni rule probları iki dilde 78.464 assertion ve her dönüşümde 4.775 olası sonraki hamleyi kontrol etti; yeni motor kusuru doğrulanmadı. Bu bağımsız tam oracle değildir. [Sınırlar](areas/rules/REPORT.md).

Seçilmiş GameStore 119/119, savaş 122/122, ekonomi 84/84, online 62/62 ve font/ilerleme 39/39 geçti; bunlar tam koşularla örtüşür. Ajanın son client validation isteği approval-service kullanım limitinde çalıştırılamadı; parent’ın ayrı normal incelenmiş isteği exact baseline replay ve 119/119’ı tamamladı. Onay atlanmadı. Online agent içerik flag’i sonrası root mevcut yerel pozitif/kurtarma testlerini ve minimal düzeltmeyi tamamladı. İlk hatalı font-path/fake-async raster denemeleri, fixture hatası ve ilk analyze uyarısı kanıtta korunur; bug veya PASS diye sayılmadı. [Client raporu](areas/client/REPORT.md) · [Online raporu](areas/online/REPORT.md).

Yerel SDK gerçek RTDB/Admin transaction’larıdır; Google yanıtları fake’tir, gerçek Auth/App Check/Play/production kabulü değildir. Tek exact localhost/demo namespace için standalone transport proxy koşulu bellekte değişti; SDK disk/proxy ortamı/header’lar korundu. [Yedi vaka](billing-sdk-summary.json). JVM/Node RAM ölçümü Android RAM’i değildir.

İlk APK derlemesi exit 0 ile tamamlandı. Disk doluluğu ilk paket denetimini klasör oluşturmada durdurdu; o denetimde hiçbir kontrol PASS sayılmadı. Tam APK SHA/ZIP CRC ile doğrulanıp aynı baytlarla korundu; yalnız byte-identical kopyalar ve tamamlanmış derleme ara çıktıları temizlendi. Derleme tekrarlanmadan aynı APK yeniden denetlendi. [Başarısızlık ve kurtarma](evidence/android/package-audit-recovery.json), [ilk komutlar](evidence/android/initial-package-audit/commands.json).

Güncel **ARM64 debug test APK’sı**: com.luno.chess / 1.6.3+19, minSdk 24/targetSdk 36; aynı debug sertifikası, 750 asset, ELF/ZIP statik 16 KB. [Paket kanıtı](android/apk-verification.json) · [SHA256](APK-SHA256SUMS). Release APK/AAB upload key eksikliğinde BLOCKED; yeni imza oluşturulmadı.

Önceki native raster SIGSEGV açık; yeni APK native cihazda oynatılmadı. Fiziksel FPS/RAM/p95–p99/uzun maç ve gerçek 16 KB çalışması yok. Üretim Firebase/Google/App Check/Integrity, Play lisans ve Console kabulü tamamlanmadı. [Kapılar](GATES.md) · [Açık sorunlar](OPEN-ISSUES.md). Canlı deploy, para, Play upload/yayın ve GitHub push yapılmadı. **RELEASE HOLD.**
''')
put('verification.json',{'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':s,'new_verified_bug_families':{'P1':1,'P2':3},'prior_family_residuals_fixed':{'P1':1,'P2':1},'concrete_defects_fixed':6,'new_verified_open_this_round':0,'global_bug_free_acceptance':'NOT ESTABLISHED','release_decision':'HOLD','real_firebase':'BLOCKED','licensed_billing':'BLOCKED','play_console':'BLOCKED','native_current_apk':'NOT RUN','real_16kb':'NOT RUN','github_push':False,'live_deploy':False,'real_money':False,'play_upload':False})
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
print({'qa_files_hashed':len(manifest),'source':s['build_source_commit'],'concrete_fixed':6,'decision':'HOLD'})
