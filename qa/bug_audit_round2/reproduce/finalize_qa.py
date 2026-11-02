from pathlib import Path
import json,hashlib,shutil,re,gzip
r=Path('/workspace/luno-review/bug-audit-round2');q=Path('/workspace/luno-chess/qa/bug_audit_round2')
g=json.loads((q/'gates.json').read_text())
reasons=[
 'Altı hata, başarısız tekrar üretimden sonra düzeltildi. Bu turda açık bırakılan doğrulanmış yeni kaynak hatası 0; bütün oyun için hatasızlık kanıtı değildir.',
 '1399 geçti / 0 başarısız / 1 atlandı. Node dosyaları gerçek TAP vakalarıyla doğrudan çalıştırıldı; atlanan opt-in test ayrıca kaydedildi.',
 '376 test geçti. 3101 senaryo / 10967 durum ve tam geçerli hamle kümesi; 0 ayrışma.',
 'Dört dar vaka geçti. Ayrı SDK bağlantısı kalıcı veriyi doğruladı. Google yanıtları fake; tek loopback proxy koşulu bellekte değiştirildi. SDK disk dosyaları, ortam ve header’lar korundu.',
 '11776 geçti / 97 başarısız / 0 atlandı. Tarihsel 97 pixel farkı açık; golden referansları değiştirilmedi.',
 'Aynı debug imzası, 750 asset, targetSdk 36 ve ELF/ZIP statik 16 KB kontrolleri geçti. Gerçek 16 KB runtime testi değildir.',
 'Sağlıklı Android ortamında kök neden veya düzelme kanıtı yok. Bu tur emülatör/cihaz testi yapılmadı.',
 'KVM, donanım GPU ve fiziksel cihaz yok; widget görüntüleri cihaz performansı değildir.',
 'Staging/üretim kimlikleri ve servis kabulü yok. Yerel SDK testi bunların yerine geçmez.',
 'Lisans hesabı, track, Play Services ve Console geçmişi yok. +19 kullanılabilirliği bilinmiyor.',
 'Mevcut upload keystore/properties yok. İmzalama koruması build’i durdurdu; kimlik değiştirilmedi.'
]
assert len(g)==len(reasons)
for row,reason in zip(g,reasons):row['reason']=reason
(q/'gates.json').write_text(json.dumps(g,ensure_ascii=False,indent=2)+'\n')
(q/'GATES.md').write_text('# Yayın kararı — RELEASE HOLD\n\n| Kapı | Durum | Kapsam ve somut engel |\n| --- | --- | --- |\n'+''.join('| '+x['gate']+' | '+x['status']+' | '+x['reason']+' |\n' for x in g))
p=q/'BUGS.md';s=p.read_text().replace('olmadan6/6','olmadan 6/6');p.write_text(s)
for name in ['assemble_report.py','update_handoff.py','finalize_qa.py','finish_pipeline.sh']:
 p=q/'reproduce'/name;shutil.copy2(r/name,p)
preflight=json.loads((r/'qa-preflight.json').read_text());(q/'evidence/qa-preflight.json').write_text(json.dumps(preflight,indent=2)+'\n')
(q/'reproduce/README.md').write_text('''# Yeniden doğrulama

Bu dizindeki betikler kayıtlı worker yollarını kullanır. Başka makinede yolların uyarlanması gerekir. Kaynak commit’i `../source.json` içindedir. Kullanılan sürümler: Flutter 3.47.1, Dart 3.13.1, OpenJDK 21.0.12, Node 22.23.3. Toolchain aktivasyonu `/workspace/toolchains/luno-env.sh` idi; proje güncellenmedi.

1. Alan raporları her kusur için önceki başarısız tekrar üretimi, kaynak hash’ini ve düzeltilmiş sonucu açıklar. Yeni regresyon testleri repodaki commit’lerdedir.
2. `run_node_direct.py` gerçek TAP case sayılarını toplar. Worker’ın dosya seviyesindeki PASS çıktısı assertion kanıtı sayılmaz.
3. `run_flutter_final.sh` analizi ve tam Flutter koşusunu çalıştırır. `summarize.py` başarılı gizli yükleyici olaylarını saymaz; başarısızlıkları saklar. Yalnız yeni oluşturulan untracked çıktılar dış kanıt dizinine taşınır; arşivlenen iki generated inventory, doğrulanmış test öncesi baytlarına döndürülür. Golden güncellenmez.
4. `post_tests.py`, yalnız test adı ve gerçek pixel hata mesajı önceki sonuçla eşleşen 97 farkı sınıflandırır; her aday görüntünün eski V239 baytlarına eşitliğini ayrıca doğrular. Bu eşitlik görsel tasarım onayı değildir.
5. Android build ve audit betikleri APK kimliği, aynı sertifika, kaynak asset baytları, ELF/ZIP statik 16 KB hizalamasını doğrular. Canonical APK dış teslim dizinindedir. Native Android, üretim Firebase ve gerçek Play testleri bu betiklerin kapsamı değildir.

Ham loglar `../logs/` altında gzip olarak bulunur. Alan logları ayrıca ilgili alan dizininde `.log.gz` adıyla korunur. Yerel SDK koşusunun bilinçli in-memory transport değişikliği ve Google fake kapsamı `../areas/runtime/REPORT.md` içinde açıklanır. Geçmiş başarısız koşular başarı sayılmaz. İncelenmemiş golden referansları değiştirilmez.
''')
manifest=[]
for p in sorted(q.rglob('*')):
 if p.is_file() and p.name!='EVIDENCE-SHA256SUMS':manifest.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(q).as_posix())
(q/'EVIDENCE-SHA256SUMS').write_text('\n'.join(manifest)+'\n')
print('Final QA manifest files:',len(manifest))
