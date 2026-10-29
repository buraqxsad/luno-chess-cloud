# V240 — RELEASE HOLD

| Kabul kapısı | Durum | Kanıt/somut engel |
| --- | --- | --- |
| V239 kaynakları, V235–V238 düzeltmeleri ve orijinal girdiler | PASS | 781 korunan orijinal girdi,4 atlas ve eski düzeltmeler korundu; runtime değişikliği yalnız loading Material bağlamı. |
| P0 backend/kurallar/hesap/ekonomi, yerel | PASS | Backend/TS tam;12 yerel Auth/RTDB suite. App-ID, tombstone, daily, concurrent action/settlement, DM/friends/privacy, receipt/recovery. |
| Üretim/staging Firebase ve App Check/Play Integrity | BLOCKED | Staging yapılandırması/kimliği ve production kabul erişimi yok. Yerel emulator gerçek cloud kabulü değildir; deploy yapılmadı. |
| Eski backend/yeni istemci, gerçek dağıtılmış sürüm | NOT RUN | V240 protocol/API/serialized model/payload değişikliği yapmaz; yerel uyumluluk regresyonları geçti. Gerçekte dağıtılmış eski backend sürümüne erişim yok. |
| Google hesap geri giriş/değişim, gerçek hesap | BLOCKED | Mock/service regresyonları geçti; uygun Play Services cihazı/hesabı yok. |
| Tam Flutter | FAIL | 11711pass/97fail; görsel karşılaştırmalar değiştirilmedi. Diğer hata0. |
| 24 kart Flutter ekran/animasyon | PASS | TR77/77, EN76/76; normal/reduced, iki yön, finite cleanup ve tested special moves. Native kapsam ayrı. |
| Gerçek Android tam oyuncu yolculuğu/24 kart | BLOCKED | İlk güncel profile APK açılışında com.luno.chess raster thread SIGSEGV/null-pointer ile kapandı; native backtrace libc extent_recycle/je_malloc ve libflutter.so içeriyor. Sonraki varsayılan V239/V240 kontrolleri 90 saniye sonunda canlıydı ve karşılama 1/3 ekranını çizdi; tutulan son 800 log satırında yeni signal yok. Bu sınırlı tekrar ilk çökmenin kök nedenini veya giderildiğini kanıtlamaz. Software diagnostic de karşılama çizdi; tutorial butonuna dokunma denemeleri 1/3 ekranını ilerletmedi, adb input yavaşlığı/SystemUI ANR görüldüğünden uygulama kaynaklı takılma kanıtlanmadı. Sağlıklı tam oyuncu zinciri/24 kart ve native performans kabulü tamamlanmadı. |
| Varsayılan renderer ile native açılış | FAIL | İlk güncel profile APK açılışında com.luno.chess raster thread SIGSEGV/null-pointer ile kapandı; native backtrace libc extent_recycle/je_malloc ve libflutter.so içeriyor. Sonraki varsayılan V239/V240 kontrolleri 90 saniye sonunda canlıydı ve karşılama 1/3 ekranını çizdi; tutulan son 800 log satırında yeni signal yok. Bu sınırlı tekrar ilk çökmenin kök nedenini veya giderildiğini kanıtlamaz. Software diagnostic de karşılama çizdi; tutorial butonuna dokunma denemeleri 1/3 ekranını ilerletmedi, adb input yavaşlığı/SystemUI ANR görüldüğünden uygulama kaynaklı takılma kanıtlanmadı. Sağlıklı tam oyuncu zinciri/24 kart ve native performans kabulü tamamlanmadı. |
| Fiziksel Android ve uzun maç FPS/build-raster p95–p99 | NOT RUN | Uygun fiziksel cihaz yok; emülatör sonuçları fiziksel diye sunulmadı. |
| API36, paket kimliği ve yerel sürüm | PASS | com.luno.chess,1.6.3+19,min24/target36; gerçek iki APK manifestinde doğrulandı. |
| versionCode19 Play geçmişinde kullanılabilirliği | BLOCKED | Console geçmişi yok; +19 korundu, kullanılabilir diye işaretlenmedi. |
| İmzalı release APK/AAB | BLOCKED | Mevcut upload imza bilgileri yok; gerçek Gradle signing guard doğru durdu. Sahte/debug release oluşturulmadı. |
| Test APK imza/hash/asset/ELF/ZIP16KB | PASS | Aynı debug sertifikası/v2,749 asset,ELF64 PT_LOAD ve zipalign -P16. Release/Play kabulü değildir. |
| Gerçek16KB runtime | NOT RUN | Erişilen API29 kernel4096B. Static align kontrolü runtime yerine sayılmadı. |
| Play Billing license: purchase/pending/cancel/restore/refund/subscription | BLOCKED | Yerel backend/adapter/recovery geçti; lisans test hesabı/track/Console yok, gerçek para kullanılmadı. |
| Privacy/Terms/hesap silme public bağlantıları | PASS | Üç GET HTTP200; Luno içerikleri ve silme talimatı var. Form/e-posta gönderilmedi; Console beyanı yerine sayılmadı. |
| Data Safety/rating/audience/store media/reviewer login | BLOCKED | Play Console erişimi yok; mevcut beyanlar ve giriş doğrulanamadı. |
| Pre-launch Report | NOT RUN | Console raporu yok; yeni rapor için gereken Play upload bu görevde yapılmadı. |
| Koşullu kapalı test/production erişimi | BLOCKED | Kişisel hesap13Kasım2023sonrası ise resmî şart en az12 tester/14 kesintisizgün. Hesap türü/tarihi/track geçmişi bilinmiyor. |
| Canlı deploy/gerçek ödeme/upload/yayın yapmama | PASS | Bu eylemler yapılmadı. |
