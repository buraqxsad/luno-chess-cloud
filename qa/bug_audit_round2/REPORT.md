# İkinci sistem taraması

**6 yeni hata bulundu ve düzeltildi: 1 P1, 5 P2. Bu turda doğrulanıp açık bırakılan yeni kaynak hatası: 0.** Bu sonuç bütün oyunun hatasız olduğunu kanıtlamaz. Eski Android çökmesi ve 97 görsel karşılaştırma farkı açık; gerçek cihaz ve servis kabulü tamamlanmadı. **RELEASE HOLD.**

Build ve son regresyon kaynağı: `9d41c5055006907ee2dafdf8e5daf70bb9f2c7a3`. Başlangıç: `b1b9c7a2f76282c6588383d5ab7926ec8b438e5f`. Düzeltmeler ayrı commit’lerde tutuldu. Son QA commit’i çalışma kodunu değiştirmez. Oyun kuralları, 24 kart, önceki düzeltmeler, çizimler, atlaslar ve imzalama kimliği korundu.

[Kök nedenler ve commit’ler](BUGS.md) · [Değişen dosyalar](CHANGED-FILES.md) · [Kapsam sonucu](scope-clean-status.json) · [Açık sorunlar](OPEN-ISSUES.md).

| Son kaynakta doğrulama | Sonuç |
| --- | --- |
| Flutter analiz | Hata ve uyarı yok |
| Tam Flutter, 437 dosya | **11776 geçti / 97 başarısız / 0 atlandı** |
| Tam backend | 1399 geçti / 0 başarısız / 1 atlandı |
| Tam TypeScript, Dart bridge etkin | 376 geçti / 0 başarısız / 0 atlandı |
| Dart/TypeScript differential | 3101 senaryo, 10967 durum ve tam geçerli hamle kümeleri; 0 ayrışma |
| Gerçek yerel RTDB/Admin SDK | 4/4 geçti; bağımsız SDK bağlantısı kalıcı veriyi doğruladı |

Koşular örtüşür; sayıları toplanmadı. Node dosyaları ayrı süreçlerde, gerçek TAP vaka sayılarıyla çalıştırıldı. Flutter’daki gizli başarılı yükleyici olayları test sayısına eklenmedi; tüm başarısızlıklar korundu. [Flutter](flutter-summary.json) · [Backend](backend-summary.json) · [TypeScript](typescript-summary.json) · [Atlanan test](skipped-tests.json).

97 başarısızlığın tamamında eski test adı ve gerçek pixel hata mesajı doğrulandı. Her aday PNG eski V239 adayıyla byte düzeyinde aynıydı. Golden görüntüleri güncellenmedi; bu eşitlik eski farkların tasarım kabulü değildir. **Tam Flutter koşusu başarısızdır.** [Sınıflandırma](evidence/flutter/failure-classification.json) · [Görüntü hash karşılaştırması](evidence/flutter/golden-comparison.json).

[24 kart kabul matrisi](cards/acceptance.md), gerçek Flutter savaş ekranında fixture transport ile geçen testlerden üretildi. Native Android kabulü değildir. Bu koşuda üretilen [TR](screenshots/current-battle-target-tr.png) ve [EN](screenshots/current-battle-target-en.png) görüntüleri widget test çıktılarıdır. Fiziksel cihaz görüntüsü veya performans ölçümü olarak sunulmadı. Kural motoruna yeni bir tam bağımsız test oracle’ı uydurulmadı; simetri ve muhasebe kontrollerinin sınırları [alan raporunda](areas/rules/REPORT.md) açıklandı. Differential için değişmeyen AOT girdileri [exact hash ile doğrulandı](evidence/differential/source-provenance.json).

Yerel SDK kabulündeki önceki timeout’un test düzeneği nedeni bulundu: Admin SDK dış faye constructor’ını kullanmıyor; standalone bundle kendi transport’unu içeriyor. Yalnız kesin localhost demo adresi için bir proxy seçimi koşulu bellekte değiştirildi. Transaction uygulaması, ortam değişkenleri, header’lar ve SDK disk dosyaları korundu. İlk üç eski vaka ile son kaynaktaki dört vaka ayrı kaydedildi; geçmiş timeout’lar başarı diye yeniden yazılmadı. Son koşu, RTDN gelmeden owned inactive subscription’ın hakkı kaldırmasını da doğruladı. Google Play yanıtları sahtedir; bu test Auth, App Check veya üretim Firebase/Play kabulü değildir. [Ayrıntılar](areas/runtime/REPORT.md) · [Son SDK sonuçları](sdk-final-summary.json).

Güncel **ARM64 debug test APK’sı** bu kaynak commit’inden üretildi: `com.luno.chess`, `1.6.3+19`, minSdk 24, targetSdk 36. Aynı debug sertifikası, kaynakla aynı 750 asset ve native ELF/ZIP statik 16 KB kontrolleri doğrulandı. Runtime payload hash’i önceki APK’dan farklıdır. [Paket kanıtı](android/apk-verification.json) · [SHA-256](APK-SHA256SUMS). Upload anahtarı bulunmadığı için release APK/AAB üretimi BLOCKED; imza kimliği değiştirilmedi.

Yeni APK native cihazda oynatılmadı. Önceki API 29 raster SIGSEGV için kök neden ve düzelme kanıtı yok. Fiziksel FPS, RAM, build/raster p95–p99, uzun maç ve gerçek 16 KB runtime testleri yapılmadı. Üretim Firebase, Google giriş, App Check, Play Integrity, lisanslı ödeme ve Play Console kabulü eksik. [Kabul kapıları](GATES.md). Canlı deploy, gerçek ödeme, Play upload/yayın ve GitHub push yapılmadı. **RELEASE HOLD.**
