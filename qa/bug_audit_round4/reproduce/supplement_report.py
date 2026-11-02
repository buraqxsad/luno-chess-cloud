from pathlib import Path
import json,re,hashlib,shutil,datetime
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round4');q=repo/'qa/bug_audit_round4'
def data(p):return json.loads(p.read_text())
def put(name,value):
 p=q/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
b=data(q/'backend-summary.json');f=data(q/'evidence/flutter/suite-outcomes.json');s=data(q/'source.json');sdk=data(q/'billing-sdk-summary.json')
assert sdk['local_sdk_acceptance']=='PASS' and sdk['counts']['pass']==7
families=[
 ('Hesap, silme ve oturum','auth|account|deletion|erasure|tombstone|bootstrap|owner|recovery'),
 ('Ekonomi, ödül ve ödeme','economy|billing|purchase|reward|daily|subscription|receipt|pass_chest|pass-chest'),
 ('Online, arkadaşlık ve mesaj','online|friendly|invite|social|dm|matchmaking|queue|settlement|ranked|presence'),
 ('Savaş, kartlar ve gizlilik','battle|card|hotseat|private|privacy|selection|timeout|resign'),
 ('Kurallar ve kayıt biçimleri','rules|engine|chess|codec|model|core|differential|wire|contract'),
 ('Tutorial, rehber ve arayüz','tutorial|guide|coach|glyph|promotion|layout|ui_|screen|settings|audio|sound|emoji|emote|deck|localization'),
 ('Güvenlik ve API sınırları','security|route|app-check|permission|boundary|authorization|deletion|erasure'),
]
rows=[]
for title,pattern in families:
 backend=[{'file':x['file'],'exit':x['exit'],'counts':x['counts']} for x in b['results'] if re.search(pattern,x['file'],re.I)]
 flutter=[{'file':name,'counts':counts} for name,counts in f.items() if re.search(pattern,name,re.I)]
 rows.append({'area':title,'backend':backend,'flutter':flutter,'overlaps_other_areas':True,'scope':'Named source/test coverage; not exhaustive, not real service or Android acceptance.'})
put('system-coverage.json',{'source_commit':s['build_source_commit'],'coverage_groups':rows,'counts_are_overlapping':True,'native_or_production_acceptance':False})
(q/'SYSTEM-COVERAGE.md').write_text('''# Sistem kapsamı

Bu tablo son gerçek test sonuçlarını alanlara bağlar. Alanlar örtüşür; dosya/test sayıları toplanmaz. Bir test adının alanla eşleşmesi bütün davranışların kabul edildiği anlamına gelmez.

| Alan | Backend dosyası | Flutter dosyası | Gerçek servis/cihaz |
| --- | ---: | ---: | --- |
'''+''.join(f"| {x['area']} | {len(x['backend'])} | {len(x['flutter'])} | Kabul edilmedi |\n" for x in rows)+'''
[Dosya ve sonuçlar](system-coverage.json). [Yeni hata/düzeltme kanıtları](BUGS.md), [24 kart](cards/acceptance.md) ve [açık kapılar](GATES.md) kapsam sınırlarını gösterir. Ayarlar, ses ve yasal/native wrapper kaynak incelemesinde bu tur ek bir doğrulanmış kusur bulunmadı; Android etkileşim ve fiziksel ses testi yapılmadı.
''')
api=next(x for x in b['results'] if x['file']=='test/api-route-boundary.test.js');log=(r/'full-backend/api-route-boundary.test.js.log').read_text()
wrong=[line.split(': ',1)[1] for line in log.splitlines() if line.startswith('# Subtest: verified but untrusted app cannot')]
assert len(wrong)==3 and api['counts']['fail']==0 and api['counts']['pass']==54
index=repo/'functions/index.js';assert 'assertTrustedAppId(appCheck)' in index.read_text()
put('app-check-source-acceptance.json',{'source_commit':s['build_source_commit'],'functions_index_sha256':hashlib.sha256(index.read_bytes()).hexdigest(),'policy_call_present_in_handler':True,'route_suite':api,'invalid_verified_app_ids_rejected_cases':wrong,'local_source_tests':'PASS','actual_production_AppCheck_Integrity':'BLOCKED','reason':'No real Google/App Check/Integrity or staging identity. Source/mocked route acceptance only.'})
# The full run executes the host-only atlas assertion. No missing timing is invented.
atlas=f.get('test/v239_atlas_observation_test.dart');assert atlas and atlas.get('success')==1 and not atlas.get('error',0)
assets=['v237-arcane-halo-atlas.webp','v238-crystal-atlas.webp','v238-binding-atlas.webp','v238-veil-atlas.webp'];a=[]
for name in assets:
 p=repo/'luno_chess/assets/native_art'/name;a.append({'asset':str(p.relative_to(repo/'luno_chess')),'file_bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
put('cards/performance-limits.json',{'source_commit':s['build_source_commit'],'current_host_atlas_test':atlas,'current_file_bytes_total':sum(x['file_bytes'] for x in a),'assets':a,'host_asserted_image_dimensions_per_atlas':[768,768],'host_asserted_rgba_bytes_total':9*1024*1024,'host_decode_timings_current':'NOT RECORDED (optional output define not provided)','android_texture_allocation':'NOT RUN','android_decode_cache_raster':'NOT RUN','physical_FPS_RAM_build_raster_p95_p99_long_match':'NOT RUN','real_16KB_runtime':'NOT RUN','performance_acceptance':'NOT RUN'})
# Admin SDK bypasses client rules: loaded rules are not a client-rule test.
text='''# Son gerçek yerel RTDB/Admin SDK kontrolü

Son sabit kaynakta **7/7** vaka geçti: 6 Billing/lease, 1 eski friendly rezervasyon kurtarma. Ayrı SDK bağlantısı kalıcı veriyi okudu.

'''+''.join('- `'+x['case']+'`\n' for x in sdk['observations'])+f'''
Kaynak `{sdk['source_commit']}`; index SHA-256 `{sdk['source_index_sha256']}`. [Ham sonuç ve gözlemler](results.json), [TAP](fixed.log.gz), [taşıma koşulu](transport-provenance.json).

RTDB 4.11.2 ve gerçek Admin SDK kullanıldı. Google/Play yanıtları fake; gerçek Auth/App Check/Functions trigger/Play testi yok. Admin işlemleri istemci güvenlik kurallarını atlar; kuralların yüklenmesi istemci rule kabulü sayılmadı. Yalnız kesin localhost/demo namespace için bundled standalone transport içindeki tek proxy seçimi koşulu bellekte değişti. SDK disk dosyası, proxy ortamı, header ve transaction kodu korunur. Dış endpoint’e bağlanma reddedilir.

Bütün süreç sınırlı süre/RAM içinde çalıştı, worker ve JVM kapatıldı, 19000 portu serbest bırakıldı; özel log kalmadı. Host JVM/Node RSS ölçümü Android RAM veya performans sonucu değildir. Gerçek Firebase/Play kabulü **BLOCKED**.
'''
(q/'areas/runtime-billing/REPORT.md').write_text(text)
for name in ['environment-monitor-reconnect.json']:
 shutil.copy2(r/name,q/'evidence'/name)
for name in ['supplement_report.py','update_handoff.py','post_build_cleanup.py','package_delivery.py']:
 shutil.copy2(r/name,q/'reproduce'/name)
p=q/'REPORT.md';text=p.read_text();text=text.replace('[Kapsam sonucu](scope-clean-status.json).','[Kapsam sonucu](scope-clean-status.json) · [Sistem kapsamı](SYSTEM-COVERAGE.md).')
text=text.replace('[Sınırlar](areas/rules/REPORT.md).','[Sınırlar](areas/rules/REPORT.md). Atlas dosyaları toplam '+str(sum(x['file_bytes'] for x in a))+' bayt; son host testi 9 MiB RGBA boyutunu doğruladı. Bu Android RAM/GPU ölçümü değildir. [Performans sınırları](cards/performance-limits.json).')
p.write_text(text)
print({'coverage_groups':len(rows),'app_check_wrong_verified_apps':len(wrong),'sdk_cases':sdk['counts']['pass'],'atlas_file_bytes':sum(x['file_bytes'] for x in a)})
