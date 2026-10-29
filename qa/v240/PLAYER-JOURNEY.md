# V240 — gerçek Android oyuncu yolculuğu

Son profile APK/commit ve her adımın ekranı `android/native-final-status.json` içinde kayıtlıdır. Widget/yerel Firebase başarıları native başarı yerine sayılmadı.

| Akış | Durum | Kanıt / neden |
| --- | --- | --- |
| Önceki test paketini kaldırma → yeni profile APK kurulumu → temiz veri | PASS | native/uninstall.json ve native/operations.json: uninstall/install/pm clear Success; gerçek Android paket yöneticisi. |
| Varsayılan açılış ve karşılama ekranını çizme | PASS (görüntü kapsamı) | screenshots/native/renderer-controls-long/v240-default-retry.png: güncel APK, karşılama 1/3, 90 saniye sonunda PID3898. Kararlılık kabulü ayrı FAIL. |
| Varsayılan native açılış kararlılığı | FAIL | logs/native-early-logcat.txt.gz: ilk güncel çalıştırmada 00:43:31 raster SIGSEGV. Kök neden ve çözüm doğrulanmadı. |
| Açılış alt çizgi düzeltmesi, native tanı çizimi | PASS (diagnostic) | screenshots/native/renderer-controls/v240-software-diagnostic.png: aynı güncel APK, intent-only software rendering ile sarı alt çizgi yok; üretim renderer ayarı değiştirilmedi. |
| Misafir hesap → Baby Luno öğretimi | BLOCKED | Karşılama 1/3 görüldü; dokunma denemeleri sonraki adıma ilerlemedi. Guest oturumu ve oynanabilir öğretim doğrulanmadı. Ekranın çizilmesi guest giriş kanıtı değildir. |
| Ana menü → deste kaydı → AI savaşı → kart kullanımı → maç sonucu | NOT RUN | Önceki native adım tamamlanmadı. Widget sonuçları bu zincirin yerine sayılmadı. |
| İlk oyundan sonra yeniden açma ve kaydı geri alma | NOT RUN | İlk oyun/kayıt native ortamda tamamlanmadı; pm clear yeniden açma kabulü değildir. |
| Gerçek Google giriş/hesap değişimi → online eşleşme → reconnect | BLOCKED | Uygun Play Services cihazı, iki test hesabı ve staging kabul erişimi yok. Guest dış ağ güvenlik duvarında kapalıydı. |
| Sonuç → ödül → mağaza, gerçek Play lisans ödemesi | BLOCKED | Native zincir tamamlanmadı; lisans test hesabı/track/Console erişimi yok. Gerçek para işlemi yapılmadı. |
| Hotseat perdesi/emoji/deste/hızlı rota, gerçek Android | NOT RUN | Yerel Flutter regresyonları geçti; native oyun ekranına ulaşılmadı. |

Tam zincir: temiz kurulum → guest → Baby Luno → menü/deste → AI/kart/sonuç/reopen → Google/online/reconnect → ödül/mağaza. Gerçek Google/Play hesabı ve lisans kabulü yapılmadı; gerçek para harcanmadı.
