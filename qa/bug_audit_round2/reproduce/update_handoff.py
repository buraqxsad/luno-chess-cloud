from pathlib import Path
import json
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round2');q=repo/'qa/bug_audit_round2'
assert (r/'pipeline-exit.txt').read_text().strip()=='0'
s=json.loads((q/'source.json').read_text());f=json.loads((q/'flutter-summary.json').read_text());b=json.loads((q/'backend-summary.json').read_text())['totals'];ts=json.loads((q/'typescript-summary.json').read_text())['totals'];d=json.loads((q/'differential-summary.json').read_text())
block=f'''## 2 Kasım — ikinci sistem taraması

**Bu turda doğrulanıp açık bırakılan yeni kaynak hatası: 0. Genel karar:
RELEASE HOLD.** [Son rapor](qa/bug_audit_round2/REPORT.md),
[kusur ve commit matrisi](qa/bug_audit_round2/BUGS.md),
[kapsam sonucu](qa/bug_audit_round2/scope-clean-status.json) ve
[açık sorunlar](qa/bug_audit_round2/OPEN-ISSUES.md). Bu, bütün oyunun hatasız olduğunun kanıtı değildir.
Build ve tam regresyon kaynağı `{s['build_source_commit']}`; son QA commit’i çalışma kodunu değiştirmez.

- 6 yeni hata bulundu ve kapatıldı: 1 P1, 5 P2. Güncel inactive owned subscription;
  billing snapshot sırası; üstü kapalı Friendly route; silme sonrası V1 admission;
  DM raporlamada konuşma üyeliği; eski push bildirimlerinin silinmesi.
  Önceki yedi düzeltme ve aynı düzeltmenin alt senaryoları yeniden sayılmadı.
- Tam backend: {b['pass']} geçti / {b['fail']} başarısız / {b['skipped']} atlandı.
  TypeScript: {ts['pass']} / {ts['fail']} / {ts['skipped']}. Differential:
  {d['scenarioCount']} senaryo, {d['stateCount']} durum ve tam geçerli hamle kümesi; 0 ayrışma.
  Analiz temiz. Tam Flutter: {f['counts'].get('success',0)} geçti /
  {f['counts'].get('error',0)} başarısız / {f['counts'].get('skip',0)} atlandı,
  {f['suites']} dosya. 97 tarihsel görsel fark açık; golden referansları korundu.
- Son gerçek yerel RTDB/Admin SDK koşusu 4/4 geçti. Bağımsız SDK bağlantısı kalıcı
  veriyi doğruladı. Önceki timeout’un test düzeneği nedeni: Admin dış faye yerine
  bundled standalone transport kullanıyor. Yalnız kesin loopback için bir proxy
  seçimi koşulu bellekte değişti; SDK disk dosyası, ortam ve header’lar korundu.
  Google Play yanıtları fake; üretim kabulü değildir.
- Güncel ARM64 debug test APK’sı üretildi: aynı imza, com.luno.chess/1.6.3+19,
  minSdk 24 / targetSdk 36, 750 asset ve ELF/ZIP statik 16 KB kontrolleri geçti.
  Mevcut upload key yok; release APK/AAB BLOCKED. +19 Play geçmişi doğrulanmadı.
- Eski API 29 raster SIGSEGV açık. Yeni APK ile native oyuncu yolculuğu, fiziksel
  FPS/RAM/p95–p99 ve gerçek 16 KB runtime NOT RUN. Gerçek Firebase/Google/App Check/
  Integrity, Play lisans/Console/Pre-launch kabulleri BLOCKED. [Kapılar](qa/bug_audit_round2/GATES.md).
- Canlı deploy, gerçek ödeme, Play upload/yayın veya GitHub push yapılmadı.
  Kanıt/APK/source bundle/QA ZIP/hash: `/workspace/luno-review/bug-audit-round2/`.

Aşağıdaki kayıtlar tarihseldir; yeni dört SDK başarısı geçmiş timeout kayıtlarını silmez.

'''
p=repo/'DEVAM.md';text=p.read_text();marker='## 1 Kasım teslimi — sistem çapında bug avı';assert marker in text and '## 2 Kasım — ikinci sistem taraması' not in text;p.write_text(text.replace(marker,block+marker,1))
p=Path('/workspace/luno-review/INCELEME.md');text=p.read_text();marker='## Güncel kabul kaydı — 1 Kasım teslimi / sistem çapında bug avı';assert marker in text
new=f'''## Güncel kabul kaydı — 2 Kasım / ikinci sistem taraması

[Son rapor](../luno-chess/qa/bug_audit_round2/REPORT.md),
[kapsam](../luno-chess/qa/bug_audit_round2/scope-clean-status.json) ve
[açık sorunlar](../luno-chess/qa/bug_audit_round2/OPEN-ISSUES.md).
Build ve tam regresyon kaynağı `{s['build_source_commit']}`.
6 yeni hata (1 P1 / 5 P2) kapandı. Bu turda doğrulanıp açık bırakılan yeni kaynak
hatası 0; bütün oyunun hatasız olduğu doğrulanmadı.
Tam backend {b['pass']}/{b['fail']}/{b['skipped']}; TypeScript {ts['pass']}/{ts['fail']}/{ts['skipped']};
Flutter {f['counts'].get('success',0)}/{f['counts'].get('error',0)}/{f['counts'].get('skip',0)}.
Analiz temiz; differential {d['scenarioCount']} senaryo/{d['stateCount']} durum, sıfır ayrışma.
Son gerçek yerel SDK 4/4 geçti; transport test düzeneğinin nedeni ve bellekteki
tek koşul değişikliği açıkça kaydedildi. Önceki başarısız koşular korunur.
Yeni ARM64 debug test APK’sı `bug-audit-round2/` içinde. Eski native SIGSEGV,
97 golden farkı, gerçek cihaz/performans/16 KB, upload key ve üretim Firebase/
Play/Console kabulü açık. **RELEASE HOLD.** Deploy/ödeme/upload/yayın/GitHub push yok.

'''
p.write_text(text.replace(marker,new+'## Önceki kabul kaydı — 1 Kasım teslimi / sistem çapında bug avı',1))
print('Updated handoff with actual final results. Runtime unchanged.')
