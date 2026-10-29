# LUNO Chess V240 — Android kabul raporu

**RELEASE HOLD.** Mevcut ortamda testler ve iki test APK’sı üretildi. İlk native açılışta kaydedilen çökme, 97 görsel test başarısızlığı ve zorunlu cihaz/Play kabulleri açık. Yayına hazır sonucu verilmedi.

Build kaynağı: `831a7ae11f28094c4b54f37415c80031ba1fd029`, dal `codex/cloud-transfer-20261027`. Tam regresyon `ac0dd98e9924544af12e96fa6c2637eb5b7d8960` üzerinde çalıştı. Aradaki tek fark, ayrıca geçen DM entegrasyon fixture’ıdır; uygulama/backend runtime kaynakları aynı. V239’un mevcut 83 dosyalık çalışma ağacı önce `1247012` ile korundu. Son QA commit’i yalnız kanıt ve devir notlarını ekler. GitHub push yapılmadı.

**Düzeltilenler: 1 üretim P2 ve 2 QA P1 kusuru.** Açılış metnindeki sarı çift alt çizgi giderildi; önce başarısız olan regresyon ardından geçti. Ses ve DM testlerinin yük altında yanlış başarısız olmasına yol açan saat sorunları düzeltildi. Üretim ses bütçesi, DM throttle ve geçerli assertion’lar korunur. [Kök nedenler, dosyalar ve commit’ler](BUGS.md).

| Son doğrulama | Sonuç |
| --- | --- |
| Tam Flutter, 430 dosya | **11711 pass / 97 fail / 0 skip** |
| Flutter analyzer | Hata/uyarı yok |
| Kart/atlas TR; kart EN | 77/77; 76/76 |
| Backend tam | 1312 pass / 0 fail / 1 opt-in skip |
| TypeScript tam, Dart bridge etkin | 376 pass / 0 fail / 0 skip |
| Dart/TS differential | 3101 senaryo, 10967 state ve legal set; 0 ayrışma, 3820 redaction kontrolü |
| Yerel Auth/RTDB | 12 ayrı suite son durumda geçti; ilk DM hatası ve takip sonucu saklandı |
| Yayın araçları | 17 preflight ve 24 Java sentetik kontrol geçti; gerçek AAB kabulü değildir |

Opt-in V220 gerçek SDK paketi ayrıca 15/15 geçti. Koşular örtüşür; sayılar toplanmadı. [Test özeti](test-summary.json), [dosya sonuçları](suite-outcomes.json) ve [ham loglar](logs) kayıtlıdır.

Flutter’daki 97 başarısızlığın tamamı tarihsel görsel karşılaştırmalardadır. Güncel 97 adayın tamamı V239 adaylarıyla byte-identical; referanslar güncellenmedi. Tam suite yeşil değildir. Bu koşuda başka Flutter test hatası yok; native çökme ayrı açık engeldir.

[24 kart matrisi](cards/acceptance.md) ve 106 güncel TR/EN PNG, gerçek Flutter savaş ekranını fixture taşıma katmanıyla sınar. Kimlik, atlas, hedef, duplicate, lifecycle, terminal cleanup, reduced motion ve belirtilen özel hareketler test edildi. Bütün kart × özel hamle kombinasyonları, native 24 kart ve fiziksel ses gecikmesi tamamlanmadı. Korunan 781 orijinal girdi, 4 atlas ve 48 Blender karesi hash/boyut/CRC ile doğrulandı.

**Native Android’de çözülmemiş çökme var.** İlk güncel profile APK açılışında `1.raster` thread’i SIGSEGV/null-pointer ile kapandı. Backtrace, libc `extent_recycle`/`je_malloc` ve `libflutter.so` içeriyor; Dart kaynaklı neden kanıtlanmadı. Sonraki varsayılan V239/V240 denemeleri 90 saniye sonunda canlıydı ve karşılama 1/3 ekranını çizdi. Son 800 satırda yeni signal görülmemesi ilk çökmenin giderildiğini kanıtlamaz. Kayıtlar ve karşılaştırma ekranları [cihaz kaydında](android/native-final-status.json) ve [native ekranlarda](screenshots/native).

Software tanı açılış düzeltmesini görüntüledi; tutorial dokunmaları sonraki adıma ilerlemedi. ADB input yavaşlığı ve SystemUI ANR nedeniyle bunun uygulama kaynaklı takılma olduğu kanıtlanmadı. Guest → tutorial → AI → Google/online → ödül/mağaza zinciri tamamlanmadı. [Adım bazında gerçek sonuçlar](PLAYER-JOURNEY.md). TR/EN, dar ekran ve büyük yazı widget testleri fiziksel cihaz kabulü değildir.

[Performans kaydı](performance.json): atlaslar diskte toplam **585174 bayt**; host RGBA/ImageCache toplamı **9 MiB**. Host decode/cache, Android RAM/GPU tüketimi değildir. Android battle FPS, build/raster p95–p99, uzun maç ve GPU texture ölçümleri **NOT RUN**. Ölçümsüz performans PASS verilmedi.

İki yeni **test APK’sı** üretildi: debug ARM64 ve profile x86_64. `com.luno.chess`, `1.6.3+19`, minSdk24/targetSdk36; aynı debug sertifikası/v2, 749 asset ve statik ELF/ZIP 16 KB kontrolü doğrulandı. [Metadata/imza](artifacts.json), [SHA-256](ARTIFACT-SHA256SUMS). Upload imzası bulunmadığından gerçek signing guard durdu: **release APK/AAB BLOCKED**. Sahte imza oluşturulmadı. Gerçek 16 KB kernel **NOT RUN**; erişilen AVD 4 KB idi. +19’un Play geçmişinde kullanılabilirliği bilinmiyor.

Public privacy, terms ve hesap silme bağlantıları HTTP200 döndü; form/e-posta gönderilmedi. Gerçek Firebase/AppCheck/Integrity, Google hesabı, Play lisans ödemesi/pending/restore/refund/subscription, Console Data Safety/rating/media/reviewer, Pre-launch Report ve gerekli kapalı test geçmişi doğrulanmadı. Bunlar **BLOCKED/NOT RUN**. Kişisel hesap 13 Kasım 2023 sonrasıysa resmî en az 12 tester/14 kesintisiz gün şartı ayrıca değerlendirilir; hesap türü/tarihi bilinmiyor.

[Güvenlik kapsamı](P0-SECURITY.md) · [Yeniden üretim](REPRODUCE.md) · [Kabul kapıları](GATES.md) · [Açık P0/P1](open-issues.json) · [Kalan kabul işi](NEXT-ACCEPTANCE.md).

Canlı deploy, gerçek para, Play upload veya kamu yayını yapılmadı. API29 VM kapatıldı; ikinci AVD açılmadı. **RELEASE HOLD korunur.**
