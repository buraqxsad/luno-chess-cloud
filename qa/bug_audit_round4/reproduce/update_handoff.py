from pathlib import Path
import json,datetime
r=Path('/workspace/luno-review/bug-audit-round4');repo=Path('/workspace/luno-chess');q=repo/'qa/bug_audit_round4'
s=json.loads((q/'source.json').read_text());f=json.loads((q/'flutter-summary.json').read_text());b=json.loads((q/'backend-summary.json').read_text());ts=json.loads((q/'typescript-summary.json').read_text());sdk=json.loads((q/'billing-sdk-summary.json').read_text())
assert sdk['local_sdk_acceptance']=='PASS' and sdk['counts']['pass']==7
body=f'''## 2 Kasım — dördüncü sistem taraması

**4 yeni hata ailesi ve önceki düzeltmelerde kalan 2 yol kapatıldı: 6 somut kusur.**
Yeni aileler 1 P1 / 3 P2; önceki ailelerdeki kapsam eksikleri 1 P1 / 1 P2.
Bu turda doğrulanıp açık bırakılan yeni kaynak kusuru 0; bütün oyunda hatasızlık
kanıtlanmadı. **RELEASE HOLD.** [Son rapor](qa/bug_audit_round4/REPORT.md),
[kök nedenler/commit’ler](qa/bug_audit_round4/BUGS.md),
[24 kart matrisi](qa/bug_audit_round4/cards/acceptance.md) ve
[açık kapılar](qa/bug_audit_round4/OPEN-ISSUES.md).

- RTDN processing lease’i başarı diye ACK ediliyordu; yarım refund ve takeover
  sahipliği düzeltildi. Kalıcı sanılan recovery yazıları/pending intent, eski
  private projection’dan pencere açılması ve Türkçe arena başlığı glifleri kapatıldı.
- Önceki eşleşme ailesinin oda/davet/legacy recovery kapsamı ve compact Pass
  kontrol yolu tamamlandı; bunlar yeni bağımsız aile diye yeniden sayılmadı.
- Tam Flutter: {f['counts'].get('success',0)} geçti / {f['counts'].get('error',0)} başarısız /
  {f['counts'].get('skip',0)} atlandı; {f['suites']} dosya. 97 tarihsel golden farkı açık.
  96 aday V239 ile aynı; bir promotion adayı Türkçe font düzeltmesi için önce/sonra
  incelendi ve exact hash ile kaydedildi. Hiçbir golden güncellenmedi. Analiz temiz.
- Tam backend: {b['totals']['pass']} / 0 / {b['totals']['skipped']}; TypeScript: {ts['totals']['pass']} / 0 / 0.
  Differential: 3101 senaryo / 10967 durum ve tam geçerli hamle kümesi, 0 ayrışma.
  Son yerel gerçek RTDB/Admin SDK: 7/7 (Billing/lease 6 + legacy recovery 1).
  Google yanıtları fake; yalnız exact localhost transport koşulu bellekte değişti.
  Gerçek Auth/App Check/Play/üretim kabulü değildir.
- Build ve tam Flutter kaynağı `{s['build_source_commit']}`. Backend/TS/differential
  `{s['backend_regression_source_commit']}` ile başladı; sonraki tek fark GameStore’daki
  redundant null guard’ın kaldırılmasıdır. İlgili backend/motor girdileri aynı;
  hash/provenance kanıtta. Son QA commit’i çalışma kodunu değiştirmez.
- Güncel ARM64 debug test APK’sı üretildi: aynı debug sertifikası,
  com.luno.chess / 1.6.3+19, minSdk 24 / targetSdk 36, 750 asset ve ELF/ZIP statik
  16 KB kontrolleri geçti. Release APK/AAB mevcut upload key yokluğunda BLOCKED.
- Önceki native raster SIGSEGV, gerçek Android yolculuğu/performans/16 KB ve
  Firebase/Google/App Check/Integrity/Play/Console kapıları açık. +19’un Play geçmişi
  bilinmiyor. Yeni emulator, canlı deploy, gerçek ödeme, Play upload/yayın veya
  GitHub push yapılmadı. Tam dış teslim `/workspace/luno-review/bug-audit-round4/`.

Aşağıdaki kayıtlar tarihseldir; önceki sonuçlar yeni sayılara eklenmez.

'''
p=repo/'DEVAM.md';text=p.read_text();assert '## 2 Kasım — dördüncü sistem taraması' not in text
at=text.index('## 2 Kasım — üçüncü sistem taraması');p.write_text(text[:at]+body+text[at:])
p=Path('/workspace/luno-review/INCELEME.md');text=p.read_text();marker='## Güncel kabul kaydı — 2 Kasım / üçüncü sistem taraması';assert marker in text
brief=f'''## Güncel kabul kaydı — 2 Kasım / dördüncü sistem taraması

[Son rapor](../luno-chess/qa/bug_audit_round4/REPORT.md),
[altı somut düzeltme](../luno-chess/qa/bug_audit_round4/BUGS.md) ve
[kabul kapıları](../luno-chess/qa/bug_audit_round4/GATES.md).
4 yeni aile (1 P1 / 3 P2) + önceki ailelerdeki 2 eksik yol (1 P1 / 1 P2) kapatıldı.
Build/Flutter `{s['build_source_commit']}`; backend/TS/motor girdileri önceki
`{s['backend_regression_source_commit']}` ile aynı. Tam Flutter {f['counts'].get('success',0)}/97/0;
backend {b['totals']['pass']}/0/1; TypeScript {ts['totals']['pass']}/0/0; differential 3101/10967/0; analiz temiz.
Yerel gerçek SDK 7/7: Billing/lease 6, legacy recovery 1; Google fake, production kabulü değil.
97 görsel çift incelendi: 96 aday aynı, bir Türkçe glif düzeltmesi exact hash ile kayıtlı;
golden değiştirilmedi. Güncel ARM64 debug APK teslimde. Native raster çökmesi,
cihaz/performans/16 KB, upload key ve Firebase/Play/Console kabulü açık. **RELEASE HOLD.**
Bu turda doğrulanıp açık bırakılan yeni kaynak kusuru 0; genel hatasızlık kanıtı değil.
Deploy/para/upload/yayın/GitHub push yok.

'''
p.write_text(text.replace(marker,brief+'## Önceki kabul kaydı — 2 Kasım / üçüncü sistem taraması',1))
print('Current handoff inserted; historical records retained.')
