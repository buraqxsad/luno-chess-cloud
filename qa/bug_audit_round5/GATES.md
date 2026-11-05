# RELEASE HOLD

| Kapı | Durum | Neden/kapsam |
| --- | --- | --- |
| Sekiz doğrulanmış kaynak düzeltmesi | PASS | 2 yeni aile ve 6 eski aile kapsam eksiği kapatıldı; genel hatasızlık kanıtı değil. |
| Flutter analiz | PASS | Son sabit kaynakta hata/uyarı yok. |
| Tam Flutter | FAIL | 11881 geçti/97 eski görsel başarısızlık/0 atlandı;448 dosya. |
| Tam backend | PASS | 1481 geçti/0 başarısız/1 atlandı;104 dosya, gerçek doğrudan TAP. |
| TypeScript/differential | PASS | 376 test;3101 senaryo/10967 durum; 0 ayrışma. |
| Yerel gerçek RTDB/Admin SDK | FAIL | 7 geçti/2 başarısız. İki yeni silme senaryosu enqueueBattleV1/createFriendlyRoom başlangıcında INVALID_ACTION400 ile durdu; erasure kabulü verilmedi. Auth/AppCheck/Google fake; Admin client rules kabulü değildir. |
| Yeni güvenlik ajanı incelemesi | BLOCKED | Otomatik içerik filtresi; yeni probe doğrulanmadı. Mevcut AppCheck/API/metadata regresyon sonuçları ayrıdır. |
| ARM64 debug APK statik kabul | PASS | Aynı debug sertifikası,750 asset,API36,ELF/ZIP statik 16 KB. |
| Önceki native raster SIGSEGV | FAIL | Kök neden/düzelme sağlıklı Android ortamında doğrulanmadı. |
| Güncel Android yolculuğu/performans/gerçek 16 KB | NOT RUN | KVM/GPU/fiziksel Android yok; emulator açılmadı. |
| Üretim Firebase/Google/App Check/Integrity | BLOCKED | Kimlik ve staging/üretim erişimi yok. |
| Play lisans Billing/Console/Pre-launch | BLOCKED | Lisans hesabı/track/Console yok;versionCode19 uygunluğu bilinmiyor. |
| Release APK/AAB | BLOCKED | Mevcut upload key/properties yok; imzalama kimliği değiştirilmedi. |
