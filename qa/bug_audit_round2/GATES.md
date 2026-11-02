# Yayın kararı — RELEASE HOLD

| Kapı | Durum | Kapsam ve somut engel |
| --- | --- | --- |
| Bu tur doğrulanan altı kaynak kusuru | PASS | Altı hata, başarısız tekrar üretimden sonra düzeltildi. Bu turda açık bırakılan doğrulanmış yeni kaynak hatası 0; bütün oyun için hatasızlık kanıtı değildir. |
| Tam backend | PASS | 1399 geçti / 0 başarısız / 1 atlandı. Node dosyaları gerçek TAP vakalarıyla doğrudan çalıştırıldı; atlanan opt-in test ayrıca kaydedildi. |
| Tam TypeScript ve differential | PASS | 376 test geçti. 3101 senaryo / 10967 durum ve tam geçerli hamle kümesi; 0 ayrışma. |
| Gerçek yerel SDK Billing | PASS | Dört dar vaka geçti. Ayrı SDK bağlantısı kalıcı veriyi doğruladı. Google yanıtları fake; tek loopback proxy koşulu bellekte değiştirildi. SDK disk dosyaları, ortam ve header’lar korundu. |
| Tam Flutter | FAIL | 11776 geçti / 97 başarısız / 0 atlandı. Tarihsel 97 pixel farkı açık; golden referansları değiştirilmedi. |
| Güncel ARM64 debug APK statik kabulü | PASS | Aynı debug imzası, 750 asset, targetSdk 36 ve ELF/ZIP statik 16 KB kontrolleri geçti. Gerçek 16 KB runtime testi değildir. |
| Önceki Android raster SIGSEGV | FAIL / UNRESOLVED | Sağlıklı Android ortamında kök neden veya düzelme kanıtı yok. Bu tur emülatör/cihaz testi yapılmadı. |
| Fiziksel Android/E2E/FPS/RAM/p95–p99/16KB | NOT RUN | KVM, donanım GPU ve fiziksel cihaz yok; widget görüntüleri cihaz performansı değildir. |
| Gerçek Firebase/Google/AppCheck/Integrity | BLOCKED | Staging/üretim kimlikleri ve servis kabulü yok. Yerel SDK testi bunların yerine geçmez. |
| Play lisans Billing ve Console beyanları/Pre-launch | BLOCKED | Lisans hesabı, track, Play Services ve Console geçmişi yok. +19 kullanılabilirliği bilinmiyor. |
| Release APK/AAB | BLOCKED | Mevcut upload keystore/properties yok. İmzalama koruması build’i durdurdu; kimlik değiştirilmedi. |
