# Açık yayın engelleri

- P1: önceki Android raster/libflutter.so SIGSEGV çözümü doğrulanmadı. Yeni APK native cihazda oynatılmadı.
- 97 eski görsel karşılaştırma FAIL. Son adayların tamamı R4 ile aynı; hiçbir golden güncellenmedi. Referans capture/font ortamı ve bazı tasarım onayları eksik.
- İki yeni yerel SDK senaryosu başlangıç API çağrısında INVALID_ACTION400 ile FAIL; silme adımlarına ulaşmadı ve ürün/harness ayrımı tamamlanmadı.
- Yeni güvenlik-agent probe’u otomatik içerik filtresinde BLOCKED; gerçek case sonucu yok. Eski geçerli güvenlik testleri ve tam backend sonucu bu eksik yeni incelemeyi kapatmaz.
- Gerçek Android yolculuğu, fiziksel FPS/RAM/build-raster p95–p99/uzun maç, GPU/texture ve gerçek 16 KB runtime NOT RUN.
- Gerçek Firebase/Auth/App Check/Integrity/Google hesap, Play lisans Billing, Console/Pre-launch ve kapalı test kabulü BLOCKED.
- Upload keystore/properties eksik; release APK/AAB yok. +19’un Play geçmişi bilinmiyor.
- Tarihsel silme taraması sınırlı sayfalı/cooperative süre kontrolü kullanır; büyük üretim veri kümesinde performans ölçülmedi. Geç kabul işleminde worker’ın canonical creation ile mevcut postgate arasında çökmesi bağımsız crash-recovery kabulü değildir.

Bu turda doğrulanmış8kusur kapatıldı. Bu sınırlı sonuç, bütün oyunda bug kalmadığını kanıtlamaz. **RELEASE HOLD.**
