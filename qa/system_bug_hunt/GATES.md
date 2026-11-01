# Yayın kapıları — RELEASE HOLD

| Kapı | Sonuç | Kanıt / somut engel |
| --- | --- | --- |
| Yeni güvenlik/hesap/ödeme/online/arayüz regresyonları | PASS | Önce başarısız tekrar üretim; sonra dar regresyonlar. Ekonomi Play yanıtları simüle. |
| Gerçek yerel RTDB Billing ek proof | FAIL / NOT COMPLETE | İki bütçeli koşu SDK zaman aşımında durdu;0 durable observation. Yerel socket adapter tekrarı da PASS olmadı; kaynak değişmedi. |
| Gerçek yerel RTDB presence rules | PASS | Owner/onDisconnect olumlu; yanlış UID/auth-null olumsuz. Önce9/3, sonra12/0. Üretim attestation değildir. |
| Backend tam | PASS | 1365 pass /0 fail /1 skip; her dosya doğrudan Node, gerçek alt test sayıları. |
| TypeScript / Dart differential | PASS | TS 376 pass; 3101 senaryo /10967 state ve tam legal set; sıfır ayrışma. |
| Tam Flutter | FAIL | 11759 pass /97 fail /0 skip. Tarihsel görsel farklar açık; golden değişmedi. |
| Yeni debug APK statik kabulü | PASS | com.luno.chess/1.6.3+19/min24/target36; aynı debug imzası;750 asset; ELF/ZIP16KB. |
| Release APK/AAB | BLOCKED | Mevcut upload key/properties yok; signing guard durdu, kimlik değiştirilmedi. |
| Yeni APK native yolculuğu | NOT RUN | Sağlıklı native cihaz kabulü yok; önceki API29 raster SIGSEGV açık. |
| Fiziksel FPS/RAM/p95–p99/gerçek 16 KB | NOT RUN | Fiziksel Android/KVM/GPU erişimi yok; statik 16 KB runtime değildir. |
| Üretim Firebase/AppCheck/Google/Integrity | BLOCKED | Hazır kimlik/servis erişimi yok; deploy yapılmadı. |
| Play lisans satın alma/restore/refund/üyelik | BLOCKED | Lisans hesabı/track ve Play Services cihazı yok; gerçek para harcanmadı. |
| Play Console/versionCode/Pre-launch/beyanlar | BLOCKED | Console geçmişi yok; +19 uygunluğu ve zorunlu mağaza kapıları doğrulanmadı. |
