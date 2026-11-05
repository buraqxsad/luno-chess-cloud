from pathlib import Path
import json,hashlib,gzip,shutil,re,subprocess,datetime
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round5');q=repo/'qa/bug_audit_round5'
def data(n):return json.loads((r/n).read_text())
def write(n,s):
 p=q/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def put(n,v):write(n,json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def cp(p,n):
 d=q/n;d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
def zipped(p,n):
 raw=p.read_text(errors='replace');raw=re.sub(r'Bearer\s+[A-Za-z0-9._-]{24,}','Bearer [withheld]',raw);raw=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[JWT withheld]',raw)
 d=q/(n+'.gz');d.parent.mkdir(parents=True,exist_ok=True)
 with d.open('wb') as f:
  with gzip.GzipFile(filename='',fileobj=f,mode='wb',mtime=0) as z:z.write(raw.encode())
for flag in ['pipeline-exit.txt','android/pipeline-exit.txt','differential/exit.txt','analyze-final-exit.txt','runtime-billing/run-exit.txt','snapshot-restore-exit.txt']:assert (r/flag).read_text().strip()=='0',flag
s=data('source-commit.json');f=data('flutter/summary.json');b=data('full-backend/summary.json');ts=data('full-typescript/summary.json');d=data('differential/v201a-differential-summary.json');sdk=data('runtime-billing/results.json');snapshot=data('snapshot-space.json');gold=data('flutter/golden-comparison.json')
assert f['done'] is not None and f['counts']=={'success':11881,'error':97} and f['suites']==448
assert b['all_pass'] and b['files']==104 and b['totals']['pass']==1481 and b['totals']['fail']==0 and b['totals']['skipped']==1
assert ts['all_pass'] and ts['totals']['pass']==376
assert data('flutter/failure-classification.json')['all_failures_are_existing_pixel_comparisons']
assert gold['checked']==97 and gold['matching_round4']==97 and gold['unreviewed_changed']==0 and not gold['goldens_updated']
assert sdk['local_sdk_acceptance']=='PASS' and sdk['counts']['pass']==9 and sdk['counts']['fail']==0 and sdk['port19000_closed_after_cleanup'] and sdk['private_logs_remaining']==0
assert not snapshot['restore_required'] and snapshot['original_sha256']==snapshot['restored_original_sha256'] and snapshot['archive_removed_after_restore']
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==s['build_source_commit']
assert not subprocess.check_output(['git','status','--porcelain'],cwd=repo).strip()
a=data('android/Luno-Chess-bug-audit-round5-debug-arm64/verification.json');assert a['source_asset_files_verified']==750 and a['same_previous_debug_certificate']
assert hashlib.file_digest(Path(a['file']).open('rb'),'sha256').hexdigest()==a['sha256']
assert data('android/release-status.json')['release_aab']=='BLOCKED'
for n,v in [('source.json',s),('flutter-summary.json',f),('backend-summary.json',b),('typescript-summary.json',ts),('differential-summary.json',d),('local-sdk-summary.json',sdk)]:put(n,v)
cp(r/'android/Luno-Chess-bug-audit-round5-debug-arm64/verification.json','android/apk-verification.json')
for n in ['baseline.json','SOURCE-COMMITS.json','flutter/failure-classification.json','flutter/golden-comparison.json','flutter/suite-outcomes.json','differential/source-provenance.json','android/commands.json','android/release-status.json','android/runtime-provenance.json','android/disk-recovery.json','android/post-build-space-recovery.json','snapshot-space.json','root-ux-result.json']:
 cp(r/n,'evidence/'+n)
for area in ['economy','client','battle','online','rules','security','runtime-billing']:
 for p in (r/area).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(r/area).as_posix();target='areas/'+area+'/'+rel
  if p.name in {'fixed-index.cjs','baseline-index.cjs','candidate-index-legacy.js','candidate-battle-v1-friendly.js'}:continue
  if p.suffix in {'.log','.tap','.jsonl','.patch','.diff'}:zipped(p,target)
  elif p.suffix in {'.json','.md','.py','.cjs','.js','.dart','.ts','.txt','.sh','.png','.gz'} or p.name=='SHA256SUMS' or p.name.endswith('.as-run'):cp(p,target)
for area in ['full-backend','full-typescript','flutter','differential','android']:
 for p in (r/area).rglob('*'):
  if p.is_file() and p.suffix in {'.log','.tap','.jsonl'}:zipped(p,'logs/'+p.relative_to(r).as_posix())
for p in r.glob('*.log'):zipped(p,'logs/'+p.name)
for n in ['run_node_direct.py','run_flutter_final.sh','run_backend_final.sh','finish_pipeline.sh','summarize.py','post_tests.py','android/build_android.py','android/audit_apk.py','post_build_cleanup.py','prepare_local_sdk.py','park_snapshot.py','restore_snapshot.py','assemble_report.py']:cp(r/n,'reproduce/'+n)
for lang in ['tr','en']:cp(r/('generated/luno_chess/qa/v230/screens/guided-target-'+lang+'.png'),'screenshots/guided-target-'+lang+'.png')
tests={};suites={};outcomes={}
for line in (r/'flutter/full.jsonl').open():
 try:e=json.loads(line)
 except ValueError:continue
 if e.get('type')=='suite':suites[e['suite']['id']]=e['suite']['path']
 elif e.get('type')=='testStart':tests[e['test']['id']]=e['test']
 elif e.get('type')=='testDone':
  t=tests.get(e['testID'],{})
  if suites.get(t.get('suiteID'),'').endswith('/test/v239_card_acceptance_test.dart'):outcomes[t['name']]=e['result']
rows=[]
for row in json.loads((repo/'qa/bug_audit_round4/cards/acceptance.json').read_text())['rows']:
 assert all(outcomes.get(n)=='success' for n in row['cases']),row['card']
 rows.append({'card':row['card'],'atlas':row['atlas'],'cases':row['cases'],'current_Flutter_TR':'PASS','separate_EN_card_run':'NOT RUN','native_Android':'NOT RUN','physical_audio_GPU_RAM':'NOT RUN'})
assert len(rows)==24
put('cards/acceptance.json',{'source_commit':s['build_source_commit'],'scope':'Actual Flutter BattleV1Screen with offline fixture transport, not Android acceptance.','rows':rows})
write('cards/acceptance.md','# 24 kart kabulü\n\nSon tam Flutter koşusunda her kartın kimlik/atlas/hedef/duplicate/ses/background ve ayrı timeout/resign vakaları geçti. Bütün kart×özel hamle birleşimleri denenmedi. EN için ayrı kart koşusu ve native Android kabulü NOT RUN.\n\n| Kart | Atlas | Flutter TR | Android |\n| --- | --- | --- | --- |\n'+''.join('| '+x['card']+' | '+x['atlas']+' | PASS | NOT RUN |\n' for x in rows)+'\n[Makine matrisi](acceptance.json). Azaltılmış hareket, özel hareket ve hızlı cast regresyonları da tam koşudadır; fiziksel ses/GPU/FPS sonucu değildir.\n')
atlas=[]
for name in ['v237-arcane-halo','v238-crystal','v238-binding','v238-veil']:
 p=repo/'luno_chess/assets/native_art'/(name+'-atlas.webp');atlas.append({'file':str(p.relative_to(repo/'luno_chess')),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
put('cards/performance-limits.json',{'source_commit':s['build_source_commit'],'atlas_file_bytes':sum(x['bytes'] for x in atlas),'assets':atlas,'host_RGBA_asserted_bytes':9*1024*1024,'host_atlas_test':data('flutter/suite-outcomes.json').get('test/v239_atlas_observation_test.dart'),'host_decode_times_current':'NOT RECORDED (optional output define unset)','Android_GPU_texture_RAM_FPS_build_raster_p95_p99_long_match':'NOT RUN','real_16kb_runtime':'NOT RUN','performance_acceptance':'NOT RUN'})
bugs=[
 ('P1',False,'Gecikmiş sezon okuması alınmış Premium Pass’i siliyordu','67c99b8','economy','Transaction denemesinde güncel saat okunur; geçerli daha yeni sezon Pass’i eski normalizer çağrısından korunur.','7 baseline:4 geçti/3 başarısız →7/7; ilgili193 koşusunda.'),
 ('P2',False,'Yarım grant sonrası doğrulanmış refund tamamlanamıyordu','1a32a99','economy','Reconcile-required claim için de grant öncesi iade işareti yazılır. Complete/granted ve eksik receipt korumaları korunur.','4 baseline:2 geçti/2 başarısız →4/4; ilgili193 koşusunda.'),
 ('P2',True,'İlk ürün kataloğu hatası mağazayı kalıcı kilitliyordu','91863e3','client','Start ve restore boş kataloğu tekrar sorgular; katalog arızası eldeki satın alma sahipliği kurtarmasını engellemez.','Birleşik9 baseline:4 geçti/5 başarısız; son9/9, ilgili75/75.'),
 ('P2',False,'Eski pending yanıtı doğrulanmış ürünü yeniden beklemeye alıyordu','91863e3','client','Sorgu başındaki ürün nesliyle güncel canlı durum karşılaştırılır; tokeni boş eski pending de yeni sonucu ezemez.','Yukarıdaki9 ve75 koşularında; ayrı hata diye iki token varyantı sayılmadı.'),
 ('P2',False,'Özel kart penceresinde eski satır yanlış kartı işliyordu','2b2ad1e','battle','Satırlar mutable indeks yerine CardId tutar; Confirm yalnız boyanmış seçim anahtarı hâlâ geçerliyken uygulanır.','7 baseline:3 geçti/4 başarısız →7/7; ilgili34/34.'),
 ('P2',True,'Onaylanan sonuç geç cleanup ile yeniden görünüyordu','b315685','online','ACK aynı transaction’da yalnız eşleşen active ve lastMatch işaretlerini temizler; peer/yeni maç korunur.','3 baseline:2 geçti/1 başarısız →3/3; ilgili17/17.'),
 ('P2',False,'Eski V1 maçlarda silinen hesabın verisi kalıyordu','60fe952','online','Sayfalı ve kaldığı yerden devam eden geçmiş temizliği; yarım publish tekrarında sayfa atlanmaz. İstemci503 doğru ilerleme hatasını korur.','Genişleyen5 baseline:1 geçti/4 başarısız; son6/6, ilgili118/118. İstemci3 baseline2/1 →3/3, ilgili24/24.'),
 ('P2',False,'Eski maç sonucu silinen özel kayıtları yeniden yazıyordu','767ae74','online','Her katılımcı yayını mevcut metadata kontrolünden geçer; geç worker temizliği yeni maç işaretlerini ve yaşayan peer’i korur.','3 baseline:1 geçti/2 başarısız →3/3; ilgili52/52.'),
]
put('bugs.json',[{'severity':sev,'new_independent_family':new,'title':title,'commit':commit,'area':area,'fix':fix,'proof':proof} for sev,new,title,commit,area,fix,proof in bugs])
write('BUGS.md','# Sekiz somut düzeltme\n\n2 yeni P2 aile; önceki ailelerde 1 P1+5 P2 kapsam eksiği. Toplam8 kusur,1 P1+7 P2. Callback/tekrar deneme alt vakaları ayrı bug olarak çoğaltılmadı.\n\n| Önem | Tür | Kusur | Commit | Düzeltme | Kanıt |\n| --- | --- | --- | --- | --- | --- |\n'+''.join('| '+sev+' | '+('Yeni aile' if new else 'Önceki ailede yeni yol')+' | ['+title+'](areas/'+area+'/REPORT.md) | `'+commit+'` | '+fix+' | '+proof+' |\n' for sev,new,title,commit,area,fix,proof in bugs))
changed=subprocess.check_output(['git','diff','--name-only',s['base_commit'],s['build_source_commit']],cwd=repo,text=True).splitlines();write('CHANGED-FILES.md','# Değişen dosyalar\n\n'+''.join('- `'+n+'`\n' for n in changed))
put('scope-clean-status.json',{'concrete_defects_fixed':8,'new_independent_families_fixed':{'P2':2},'prior_family_residual_paths_fixed':{'P1':1,'P2':5},'verified_new_source_defects_open_this_round':0,'new_security_probe':'BLOCKED_NOT_VALIDATED','global_bug_free_acceptance':'NOT ESTABLISHED','release_decision':'HOLD'})
put('skipped-and-blocked.json',[{'scope':'backend','file':'functions/test/v220-firebase-integration.test.js','status':'SKIPPED','reason':'V220_DB_INTEGRATION not enabled; local SDK does not relabel this skip.'},{'scope':'new security-agent investigation','status':'BLOCKED / NOT RUN','reason':'Agent content filter stopped the turn for possible cybersecurity risk. Its new scratch produced only a file-wrapper/harness failure, not4 real case results. It was preserved externally and not retried, rephrased or reassigned; no source/accepted-test assertions removed and no new security PASS claimed.'}])
gates=[
 ('Sekiz doğrulanmış kaynak düzeltmesi','PASS','2 yeni aile ve6 eski aile kapsam eksiği kapatıldı; genel hatasızlık kanıtı değil.'),
 ('Flutter analiz','PASS','Son sabit kaynakta hata/uyarı yok.'),
 ('Tam Flutter','FAIL',f"{f['counts']['success']} geçti/97 eski görsel başarısızlık/0 atlandı;448dosya."),
 ('Tam backend','PASS','1481 geçti/0 başarısız/1 atlandı;104dosya, gerçek doğrudan TAP.'),
 ('TypeScript/differential','PASS','376 test;3101senaryo/10967durum;0ayrışma.'),
 ('Yerel gerçek RTDB/Admin SDK','PASS','9/9:6finansal,1legacy rezervasyon,2yeni silme akışı. Auth/App Check/Google yanıtları fake; istemci kuralları/Admin rolü farklı.'),
 ('Yeni güvenlik ajanı incelemesi','BLOCKED','Otomatik içerik filtresi; yeni probe doğrulanmadı. Mevcut AppCheck/API/metadata regresyon sonuçları ayrıdır.'),
 ('ARM64 debug APK statik kabul','PASS','Aynı debug sertifikası,750asset,API36,ELF/ZIP statik16KB.'),
 ('Önceki native raster SIGSEGV','FAIL','Kök neden/düzelme sağlıklı Android ortamında doğrulanmadı.'),
 ('Güncel Android yolculuğu/performans/gerçek16KB','NOT RUN','KVM/GPU/fiziksel Android yok; emulator açılmadı.'),
 ('Üretim Firebase/Google/App Check/Integrity','BLOCKED','Kimlik ve staging/üretim erişimi yok.'),
 ('Play lisans Billing/Console/Pre-launch','BLOCKED','Lisans hesabı/track/Console yok;versionCode19 uygunluğu bilinmiyor.'),
 ('Release APK/AAB','BLOCKED','Mevcut upload key/properties yok; imzalama kimliği değiştirilmedi.'),
]
put('gates.json',[{'gate':n,'status':v,'reason':reason} for n,v,reason in gates]);write('GATES.md','# RELEASE HOLD\n\n| Kapı | Durum | Neden/kapsam |\n| --- | --- | --- |\n'+''.join('| '+n+' | '+v+' | '+reason+' |\n' for n,v,reason in gates))
write('OPEN-ISSUES.md','''# Açık yayın engelleri

- P1: önceki Android raster/libflutter.so SIGSEGV çözümü doğrulanmadı. Yeni APK native cihazda oynatılmadı.
- 97 eski görsel karşılaştırma FAIL. Son adayların tamamı R4 ile aynı; hiçbir golden güncellenmedi. Referans capture/font ortamı ve bazı tasarım onayları eksik.
- Yeni güvenlik-agent probe’u otomatik içerik filtresinde BLOCKED; gerçek case sonucu yok. Eski geçerli güvenlik testleri ve tam backend sonucu bu eksik yeni incelemeyi kapatmaz.
- Gerçek Android yolculuğu, fiziksel FPS/RAM/build-raster p95–p99/uzun maç, GPU/texture ve gerçek16KB runtime NOT RUN.
- Gerçek Firebase/Auth/App Check/Integrity/Google hesap, Play lisans Billing, Console/Pre-launch ve kapalı test kabulü BLOCKED.
- Upload keystore/properties eksik; release APK/AAB yok. +19’un Play geçmişi bilinmiyor.
- Tarihsel silme taraması sınırlı sayfalı/cooperative süre kontrolü kullanır; büyük üretim veri kümesinde performans ölçülmedi. Geç kabul işleminde worker’ın canonical creation ile mevcut postgate arasında çökmesi bağımsız crash-recovery kabulü değildir.

Bu turda doğrulanmış8kusur kapatıldı. Bu sınırlı sonuç, bütün oyunda bug kalmadığını kanıtlamaz. **RELEASE HOLD.**
''')
write('APK-SHA256SUMS',a['sha256']+'  '+Path(a['file']).name+'\n')
write('REPORT.md',f'''# Beşinci sistem taraması

**8 somut kusur kapatıldı:2yeni P2 aile ve önceki ailelerde1P1+5P2 yeni kapsam eksiği.** Bu turda doğrulanıp açık bırakılan yeni kaynak kusuru0. Yeni güvenlik incelemesinin bir bölümü BLOCKED; bütün oyunda hatasızlık kanıtlanmadı. **RELEASE HOLD.**

Alınmış Premium Pass’in eski sezon okumasıyla kaybı; yarım grant sonrası refund; mağaza kataloğu toparlanması; eski pending sahiplik yanıtı; özel kart seçimindeki stale callback; ACK/cleanup; eski V1 geçmişinin silinmesi ve legacy maçların silinmiş veriyi geri yazması düzeltildi. [Sekiz kök neden/commit](BUGS.md) · [Dosyalar](CHANGED-FILES.md) · [Kapsam](scope-clean-status.json).

Tam regresyon ve APK aynı `{s['build_source_commit']}` commit’indendir. Kaynak dalı,24kart, sanat/atlaslar, V235–V240 düzeltmeleri ve debug imza kimliği korundu. Yeni kart/mod/animasyon altyapısı veya framework yükseltmesi eklenmedi.

| Kontrol | Sonuç |
| --- | --- |
| Flutter analiz | Temiz |
| Tam Flutter/448dosya | **11881 geçti/97 başarısız/0 atlandı** |
| Backend/104dosya |1481 geçti/0 başarısız/1 atlandı |
| TypeScript |376/376 |
| Dart/TS differential |3101senaryo/10967durum ve tam geçerli hamle kümeleri;0ayrışma |
| Yerel gerçek RTDB/Admin SDK |9/9:6 finansal+1 legacy reservation+2 yeni silme akışı |

Koşular örtüşür, sayıları toplanmadı. Seçilmiş ekonomi193/193, billing75/75, özel kart34/34, online ACK17/17, tarihsel silme118/118, legacy52/52 ve istemci silme24/24 geçti. Ayarlar/ölçüm izni67/67. Motorun yeni bounded Node30/30 ve host Dart CLI30/30 kontrollerinde yeni kusur doğrulanmadı;6433Dart assertion/657final branch. Tek özel başlangıç yerleşiminden30iz; bütün reachable durumlar veya bağımsız tam oracle değildir. Bu Dart koşusu Android cihaz testi değildir. [Motor sınırları](areas/rules/REPORT.md).

Tam Flutter’daki97hata aynı eski pixel karşılaştırmalarıdır ve97adayın tamamı R4 ile byte-identical. Yeni görsel kabul verilmedi; hiçbir golden değişmedi. **Tam Flutter FAIL.** [Sınıflandırma](evidence/flutter/failure-classification.json) · [Hash karşılaştırması](evidence/flutter/golden-comparison.json). [24kart matrisi](cards/acceptance.md) · [Dosya/RAM/performance sınırları](cards/performance-limits.json) ve [TR](screenshots/guided-target-tr.png)/[EN](screenshots/guided-target-en.png) görüntüleri gerçek Flutter widget/fixture çıktılarıdır; Android ekran görüntüsü değildir.

Yeni güvenlik ajanının turu otomatik içerik filtresinde olası siber güvenlik riskiyle durdu; probe yalnız file-wrapper/harness failure üretmişti,4gerçek vaka sonucu yok. Doğrulanmamış scratch dış kanıtta saklandı; yeniden ifade edilip başka ajana verilmedi veya yeni güvenlik PASS sonucu sayılmadı. Mevcut AppCheck12 ve günlük ödül5baseline kontrolü ile tam API/security regresyonları ayrı geçerli sonuçlardır. [Blokaj](areas/security/BLOCKED.json). Online ajan son aşamada model kullanım limitine takıldı; root verilen minimal client patch’i ve24/24 normal onaylı yerel testi tamamladı. İlk sandbox/yanlış test yolu/fixture denemeleri kanıtta korunur; bug/PASS sayılmadı.

Yerel SDK gerçek RTDB/Admin transaction’larını ve bağımsız checker bağlantısını kullanır. Auth/App Check/Google yanıtları fake; Admin işlemleri client rules kabulü değildir. Yalnız exactlocalhost/demo namespace için standalone proxy koşulu bellekte değişti; proxy/header/SDKdisk ve DB transaction mantığı korundu. Gerçek Firebase/Google/Play kabulü değildir. [Dokuz vaka](local-sdk-summary.json).

Disk bütçesi için yalnız durmuş emulator snapshot RAM’i geçici kayıpsızgzip olarak saklandı; açılmadı. Test/paket sonrasında orijinal1426527045bayt veSHA256 doğrulanarak geri kondu, geçici arşiv silindi. Oyun asseti/QAfixture veya araç kurulumu silinmedi. [Byte koruma kanıtı](evidence/snapshot-space.json). APK kopyaları erken temizlenerek R4’teki disk taşması tekrar edilmedi; yalnız yeniden üretilebilir ara çıktılar kaldırıldı.

Güncel ARM64 **debug test APK’sı** üretildi:com.luno.chess/1.6.3+19,minSdk24/targetSdk36; aynı debug sertifikası,750asset, ELF/ZIP statik16KB. [Paket kimliği/hash/imza](android/apk-verification.json) · [SHA256](APK-SHA256SUMS). Release APK/AAB mevcut upload key eksikliğinde BLOCKED; yeni imza oluşturulmadı.

Önceki native raster çökmesi,97görsel fark, gerçek cihaz/performans/16KB ve Firebase/Play/Console kabulleri açık. [Kapılar](GATES.md) · [Açık sorunlar](OPEN-ISSUES.md) · [Atlanan/bloke testler](skipped-and-blocked.json). Canlı deploy, gerçek ödeme, Play upload/yayın veya GitHub push yapılmadı. **RELEASE HOLD.**
''')
put('verification.json',{'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':s,'concrete_defects_fixed':8,'new_independent_families':{'P2':2},'prior_family_residuals':{'P1':1,'P2':5},'new_security_probe':'BLOCKED_NOT_VALIDATED','global_bug_free_acceptance':'NOT ESTABLISHED','release_decision':'HOLD','real_firebase':'BLOCKED','licensed_billing':'BLOCKED','play_console':'BLOCKED','native_current_apk':'NOT RUN','real_16kb_runtime':'NOT RUN','github_push':False,'live_deploy':False,'real_money':False,'play_upload':False,'snapshot_restored_verified':True})
write('reproduce/README.md','''# Yeniden çalıştırma

Pinned Flutter3.47.1/Dart3.13.1/Java21/Node22; önce /workspace/toolchains/luno-env.sh. Betikler kayıtlı worker yollarını içerir; farklı makinede yolları uyarlayın. .log/.tap/.jsonl/.patch/.diff ham içerikleri gzip’tedir; açarak kullanın. Gzip geçerli patch context baytlarını korur. Doğrulanmamış güvenlik scratch’i veya external-import proposal testleri kabul edilmiş CI testleri değildir; normal test kümesine eklemeyin. Gerçek regresyonlar kaynakta kendi portable test dosyalarındadır.

SDK yalnız exactdemo localhost namespace, fake Google/Auth ve dar in-memory transport koşulu ile çalışır; production kabulü değildir. Snapshot RAM’i park/restore betikleri sadece durmuş emulator için geçici disk içindir; RAM içeriği Git’e girmez. Manifest, kanıt byte’larını listeler.
''')
for p in q.rglob('*.md'):
 text=p.read_text()
 def fix(m):
  candidate=p.parent/m[1]
  return ']('+m[1]+'.gz)' if not candidate.exists() and Path(str(candidate)+'.gz').exists() else m[0]
 p.write_text(re.sub(r'\]\(([^)]+)\)',fix,text))
write('EVIDENCE-SHA256SUMS',''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(q).as_posix()+'\n' for p in sorted(q.rglob('*')) if p.is_file() and p.name!='EVIDENCE-SHA256SUMS'))
print({'qa_files':sum(p.is_file() for p in q.rglob('*')),'source':s['build_source_commit'],'concrete_fixed':8,'decision':'HOLD'})
