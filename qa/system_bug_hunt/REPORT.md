# LUNO Chess — sistem çapında bug avı

**7 yeni doğrulanmış hata ailesi kapatıldı: 3 P1, 4 P2. RELEASE HOLD korunur.** Kullanıcı isteğiyle altı ajan kimlik/güvenlik, ekonomi/ödeme, online, kurallar, client ve battle/tutorial alanlarını inceledi. Ortam devamından sonra ekonomi fix’i tamamlandı ve ayrıca bağımsız salt-okunur review yapıldı.

Son kaynak/build commit’i `219b1daf5f2329c558bc1ac7a3cf6c781e316514`; başlangıç `fc11b702876d0d5c181c545bf6e52319fdddc520`. [Kök neden ve test kanıtları](BUGS.md) · [Dosyalar](CHANGED-FILES.md) · [24 kart matrisi](cards/acceptance.md). Son QA/devir commit’i runtime değiştirmez. V237/V238 kartlar, canlı Luno, oyun kuralları, varlıklar, oyuncu hakları ve mevcut imzalama kimliği korunur.

| Son kaynak doğrulaması | Sonuç |
| --- | --- |
| Tam Flutter, 435 dosya | **11759 pass /97 fail /0 skip** |
| Analyzer | Hata/uyarı yok |
| Tam backend |1365 pass /0 fail /1 skip|
| Tam TypeScript, Dart bridge etkin |376 pass /0 fail /0 skip|
| Dart/TS differential |3101 senaryo /10967 state ve tam legal set; sıfır ayrışma|
| Gerçek yerel presence RTDB rules |12/12; eski kaynakta 3 başarısızlık tekrarlandı|

İlk analiz, yeni testlerde bir kullanılmayan import ve iki brace stil uyarısında durdu; tam Flutter henüz başlamamıştı. Yalnız test stili düzeltildi, ilk hata kaydı kanıtta korunur. Örtüşen koşuların sayıları toplanmadı. Node worker sarmalayıcısının dosya başına PASS çıktısı assertion kabulü sayılmadı; backend/TS tam regresyonu her dosyayı ayrı doğrudan Node sürecinde gerçek TAP case sayılarıyla çalıştırdı. [Backend](backend-summary.json) · [TS](typescript-summary.json) · [Atlanan test ve neden](skipped-tests.json). Kullanılan engine/Dart girdileri son kaynakla hash eşitliğiyle bağlandı; ekonomi değişiklikleri bu girdilere girmez.

Tam Flutter’daki tarihsel görsel başarısızlıklar açıkça FAIL tutulur. Test adı, pixel hata mesajı ve aday hash karşılaştırması [kanıtta](evidence/flutter/failure-classification.json); golden referansları güncellenmedi. 97 güncel aday PNG önceki V239 adaylarıyla byte-identical; bu tasarım kabulü değildir. [Görüntü hash karşılaştırması](evidence/flutter/golden-comparison.json). [Flutter özeti](flutter-summary.json). Testler silinmedi; önceki tam profile deepEqual assertion’ı yalnız beklenen yeni sıfır-tutarlı refund metadata’sını kapsayacak biçimde korundu; fazladan provider/claims sorgusu beklentileri tam sayımla güncellendi.

Güncel **ARM64 debug test APK’sı** kesin commit’ten üretildi: `com.luno.chess`, `1.6.3+19`, min24/target36, aynı debug sertifikası/v2,750 asset kaynakla birebir; ELF/ZIP statik 16 KB PASS. [Paket/imza/asset kanıtı](android/apk-verification.json) · [SHA-256](APK-SHA256SUMS). Önceki APK yeniden adlandırılmadı; kernel payload hash’i değişti. Bu paket native/Play kabulü değildir. Mevcut upload key bulunmadığından release APK/AAB BLOCKED; yeni imza yok.

Gerçek Google/Play yanıtları testlerde simüleydi; yerel RTDB rules gerçek değerlendirmesi production AppCheck/attestation değildir. Ek Billing gerçek SDK proof’u iki bütçeli denemede timeout oldu ve durable observation üretmedi; **FAIL / NOT COMPLETE** korunur. [SDK raporu](areas/economy/sdk-proof/REPORT.md). Bu başarısız denemeler unit/backend PASS sayısına katılmadı. Yeni APK native cihazda çalıştırılmadı; V240 API29 raster SIGSEGV çözülmüş sayılmaz. Fiziksel FPS/RAM/p95–p99, gerçek 16 KB, Firebase/Google/Play Integrity, lisanslı Billing ve Console/Pre-launch koşulları tamamlanmadı. [Kapılar ve somut nedenler](GATES.md) · [Açık P1 ve kabul engelleri](OPEN-ISSUES.md). Kaynak düzeltmesi canlı backend’e deploy edilmedi; gerçek servis bu fix’leri kullanıyor diye varsayılmamalı.

Canlı deploy, gerçek ödeme, Play upload/yayın ve GitHub push yapılmadı. **RELEASE HOLD.**
