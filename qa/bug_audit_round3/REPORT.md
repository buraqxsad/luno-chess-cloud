# Üçüncü sistem taraması

**Bu turda 9 yeni hata doğrulandı ve kapatıldı: 2 P1, 7 P2. Bu turda açık bırakılan doğrulanmış yeni kaynak hatası: 0.** Bütün oyunun hatasız olduğu kanıtlanmadı. **RELEASE HOLD.**

İlk satın alma kaydından önceki iade altın basabiliyor; eski eşleşme isteği üçüncü oyuncuyu kilitleyebiliyordu. Diğer düzeltmeler pending ödeme, silinen puan/davet kaydı, hesap değişimi sırasında kayıt ve bootstrap, eski savaş seçimi ve cold Firebase cache davranışını kapsar. [Dokuz kök neden ve commit](BUGS.md) · [Değişen dosyalar](CHANGED-FILES.md) · [Kapsam sonucu](scope-clean-status.json).

Build kaynağı `8b12d5aa649d26b1eb67dd1252922fea53532bbd`. Runtime’ın sabitlendiği ve tam Flutter’ın çalıştığı commit `000faaaada3106bc5bf306d02498821f046773e2`. Sonraki tek test commit’i iki backend testindeki provider çağrı beklentisini ilk registration’daki ikinci doğrulamaya uyarladı; çalışma kodu ve bütün Flutter girdileri byte düzeyinde aynı. Son backend/TS/differential ve APK bu build kaynağıyla doğrulandı. Kaynak dalı, 24 kart, önceki fix’ler, çizimler/atlaslar ve imza kimliği korundu.

| Doğrulama | Sonuç |
| --- | --- |
| Analiz | Hata/uyarı yok |
| Tam Flutter, 441 dosya | **11803 geçti /97 başarısız /0 atlandı** |
| Tam backend, 97 dosya | 1437 geçti /0 başarısız /1 atlandı |
| Tam TypeScript | 376 geçti /0 başarısız /0 atlandı |
| Dart/TS differential | 3101 senaryo/10967 durum ve tam geçerli hamle kümeleri, 0 ayrışma |
| Yerel Billing SDK | 5/5; yeni unmatched-refund vakası dahil, ayrı SDK bağlantısı kalıcı gold/receipt/event verisini doğruladı |
| Yerel cold-friendly SDK | 4/4; exact source baseline 3/4; bağımsız bağlantı davet silinmesini doğruladı |

Örtüşen koşu sayıları toplanmadı. Node dosyaları doğrudan çalıştırıldı; dosya-wrapper PASS gerçek test kabulü sayılmadı. [Tam Flutter](flutter-summary.json) · [Backend](backend-summary.json) · [TypeScript](typescript-summary.json) · [Atlanan test](skipped-tests.json). [Diferansiyel kaynak/hash kanıtı](evidence/differential/source-provenance.json).

97 Flutter başarısızlığı aynı eski test adları, gerçek pixel hata mesajları ve V239 ile aynı aday PNG baytlarıyla doğrulandı. Golden’lar güncellenmedi; eski farkların tasarım kabulü verilmedi. **Tam Flutter koşusu FAIL.** [Sınıflandırma](evidence/flutter/failure-classification.json) · [Görüntü karşılaştırması](evidence/flutter/golden-comparison.json). [24 kart matrisi](cards/acceptance.md) gerçek Flutter savaş ekranı/fixture kapsamıdır. [TR](screenshots/guided-target-tr.png) ve [EN](screenshots/guided-target-en.png) görüntüleri widget test çıktılarıdır; Android cihaz görüntüsü değildir.

Yeni kural probları 24 kartta private-world noninterference, 4328 malformed-action atomic rejection, codec ve takip edilen perft referanslarını kontrol etti; yeni motor hatası doğrulanmadı. Bu, tam bağımsız oracle değildir. [Sınırlar ve gerçek sayılar](areas/rules/REPORT.md). Ayarlar, ses, hata/legal/native wrapper kaynak incelemesi ve mevcut tam regresyon ek bir doğrulanmış kusur üretmedi; fiziksel/native kabulü değildir.

Yerel SDK’lar gerçek RTDB/Admin SDK transaction’larıdır; Google yanıtları ve ilgili Auth/admission bağımlılıkları fake’tir. Yalnız kesin localhost/demo namespace için standalone transport’taki bir proxy seçimi koşulu bellekte değiştirildi. Proxy ortamı, header’lar ve SDK disk dosyaları korunur. [Billing 5 vaka](billing-sdk-summary.json) · [Cold-friendly 4 vaka](friendly-sdk-summary.json) · [Runtime raporu](areas/runtime/REPORT.md). Bunlar üretim Firebase/App Check/Play kabulü değildir.

İlk backend koşusunda 1420 geçti/17 başarısız/1 atlandı: 15 spawn EPERM ve 2 eski provider-call beklentisi. Başarısız loglar saklandı. Gerekli yerel süreç izniyle son 97 dosya yeniden çalıştırıldı; iki testin exact verify 2 / consume 1, tek grant ve replay’de ek çağrı yok şartları korundu. Paketleme betiğinin dış exit-code aktarımı da düzeltildi; ilk prerequisite failure APK üretmedi ve PASS sayılmadı. [İlk koşu sınıflandırması](evidence/initial-final-attempt/CLASSIFICATION.json).

Güncel ARM64 **debug test APK’sı** üretildi: `com.luno.chess`, `1.6.3+19`, minSdk 24 / targetSdk 36; aynı debug sertifikası, 750 asset ve ELF/ZIP statik 16 KB kontrolleri geçti. [Paket kanıtı](android/apk-verification.json) · [SHA-256](APK-SHA256SUMS). Release APK/AAB mevcut upload key yokluğunda BLOCKED; yeni imza oluşturulmadı.

Önceki API 29 raster SIGSEGV açık. Yeni APK native cihazda oynatılmadı; fiziksel FPS/RAM/p95–p99, uzun maç ve gerçek 16 KB çalışma testi yok. Gerçek Firebase/Google/App Check/Integrity, Play lisanslı ödeme ve Console kabulü tamamlanmadı. [Kapılar](GATES.md) · [Açık sorunlar](OPEN-ISSUES.md). Canlı deploy, gerçek ödeme, Play upload/yayın veya GitHub push yapılmadı. **RELEASE HOLD.**
