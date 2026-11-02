from pathlib import Path
import json
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round3');q=repo/'qa/bug_audit_round3'
s=json.loads((q/'source.json').read_text());f=json.loads((q/'flutter-summary.json').read_text());b=json.loads((q/'backend-summary.json').read_text())['totals'];ts=json.loads((q/'typescript-summary.json').read_text())['totals'];sdk=json.loads((q/'billing-sdk-summary.json').read_text())
assert sdk['local_sdk_acceptance']=='PASS' and sdk['counts']['pass']==5
block=f'''## 2 Kasım — üçüncü sistem taraması

**9 yeni hata kapatıldı: 2 P1, 7 P2. Bu turda açık bırakılan doğrulanmış yeni kaynak
hatası: 0. Genel karar RELEASE HOLD.** [Son rapor](qa/bug_audit_round3/REPORT.md),
[dokuz kök neden/commit](qa/bug_audit_round3/BUGS.md),
[kapsam](qa/bug_audit_round3/scope-clean-status.json) ve
[kabul kapıları](qa/bug_audit_round3/GATES.md). Bütün oyunun hatasız olduğu kanıtlanmadı.

- P1: ilk consumable claim kaydından önce ACK edilen refund sonrası eski provider
  yanıtından altın basılması; eski enqueue request tekrarının üçüncü oyuncuyu
  deterministik match ID çakışmasında kilitlemesi. İki yol da kontrol/regresyonla kapatıldı.
- P2: iptal edilen pending ödeme kilidi; silme sonrası rating index kimliği;
  departure archive son edit kaybı; guest bootstrap’ın yeni oturumu devralması;
  eski savaş seçimine ait Play/Discard/Pass komutları; geç V1 davet metadata’sı;
  gerçek Admin SDK cold-null cache’in geçerli daveti404 reddetmesi.
- Tam Flutter {f['counts'].get('success',0)} geçti /{f['counts'].get('error',0)} başarısız /
  {f['counts'].get('skip',0)} atlandı; {f['suites']} dosya. 97 tarihsel görsel fark açık;
  adaylar eski V239 baytlarıyla aynı, golden değiştirilmedi. Analiz temiz.
  Tam backend {b['pass']}/{b['fail']}/{b['skipped']}; TypeScript {ts['pass']}/0/0;
  differential3101senaryo/10967durum ve tam legal set, sıfır ayrışma.
- Yerel gerçek RTDB/Admin SDK: Billing5/5 (yeni ACKed-unmatched refund dahil),
  cold-friendly4/4. Google ve ilgili Auth/admission bağımlılıkları fake; yalnız
  localhost transport koşulu bellekte değişti, proxy/header/SDKdisk korundu.
  İlk tamamlanmamış ek SDK koşusu ve diğer ilk başarısızlıklar kanıtta korunur.
- Build kaynağı `{s['build_source_commit']}`; tam Flutter’ın çalıştığı runtime
  `{s['flutter_regression_source_commit']}` ile byte düzeyinde aynı. Son test commit’i
  yalnız backend verify-call beklentilerini ikinci registration kontrolüne uyarladı;
  gold/consume/idempotency assertion’ları korundu. Son backend/TS/differential yeni HEAD’de.
- Yeni ARM64 debug test APK’sı: aynı debug imzası, com.luno.chess/1.6.3+19,
  minSdk24/targetSdk36,750asset, ELF/ZIP statik16KB kontrolleri geçti.
  Release upload key yok: imzalı release APK/AAB BLOCKED; +19 Play geçmişi bilinmiyor.
- Önceki native raster SIGSEGV ve gerçek Android yolculuğu/performans/16KB açık.
  Üretim Firebase/Google/AppCheck/Integrity, Play lisans/Console kabulü tamamlanmadı.
  Yeni emulator/cihaz testi, canlı deploy, para, Play upload/yayın veya GitHub push yok.
  Tam dış teslim `/workspace/luno-review/bug-audit-round3/` içindedir.

Aşağıdaki kayıtlar tarihseldir; önceki tur sonuçları yeni sayılara eklenmez.

'''
p=repo/'DEVAM.md';text=p.read_text();marker='## 2 Kasım — ikinci sistem taraması';assert marker in text and '## 2 Kasım — üçüncü sistem taraması' not in text;p.write_text(text.replace(marker,block+marker,1))
p=Path('/workspace/luno-review/INCELEME.md');text=p.read_text();marker='## Güncel kabul kaydı — 2 Kasım / ikinci sistem taraması';assert marker in text
new=f'''## Güncel kabul kaydı — 2 Kasım / üçüncü sistem taraması

[Son rapor](../luno-chess/qa/bug_audit_round3/REPORT.md) ve
[kapılar](../luno-chess/qa/bug_audit_round3/GATES.md).
9 yeni hata (2 P1 /7 P2) kapandı; bu turda açık doğrulanmış yeni kaynak hatası0,
bütün oyunda hatasızlık kanıtlanmadı. Build `{s['build_source_commit']}`;
Flutter runtime `{s['flutter_regression_source_commit']}` aynı baytlarla korundu.
Son test commit’i yalnız iki backend testinde verify2/consume1/replay çağrı beklentisini güncelledi.
Tam Flutter {f['counts'].get('success',0)}/{f['counts'].get('error',0)}/{f['counts'].get('skip',0)};
backend {b['pass']}/{b['fail']}/{b['skipped']}; TypeScript {ts['pass']}/0/0;
differential3101/10967/sıfırayrışma, analiz temiz.
Gerçek yerel RTDB/Admin SDK Billing5/5, cold-friendly4/4; production Google/Auth/AppCheck kabulü değil.
İlk SDK timeout ve test yürütme hataları korunur. Güncel ARM64 debug APK dış teslimde.
Native raster SIGSEGV,97golden farkı, realdevice/perf/16KB, uploadkey ve gerçek
Firebase/Play/Console kapıları açık. **RELEASE HOLD.** Deploy/para/upload/yayın/GitHubpush yok.

'''
p.write_text(text.replace(marker,new+'## Önceki kabul kaydı — 2 Kasım / ikinci sistem taraması',1))
print('Handoff updated; production/runtime unchanged.')
