# Tutorial iyileştirmesi — RELEASE HOLD

| Kapı | Sonuç | Somut kapsam/engel |
| --- | --- | --- |
|Canlı Luno / ilk adımlar / lifecycle, Flutter|PASS|22 yeni özellik +8 güvenlik testi; güncel welcome ve varsa battle PNG. Native kabul değildir.|
|Premium ve ödeme kilidi yarışları, yerel|PASS|2 P1 kusur önce failing test ile üretildi;12 yeni backend ve6 yeni istemci senaryosu, mevcut ilgili regresyonlar geçti.|
|Tam backend / TypeScript / differential|PASS|Backend 1324/0/1; TS 376/0/0; 3101 senaryo, sıfır ayrışma.|
|Tam Flutter|FAIL|11747 pass /97 fail; eski pixel karşılaştırmaları açık, golden güncellemesi yok.|
|Yeni test APK kimlik/imza/hash/asset/ELF/ZIP|PASS|Aynı debug sertifikası;750 asset;1.6.3+19/min24/target36; statik16KB doğrulandı.|
|İmzalı yayın APK/AAB|BLOCKED|Mevcut upload anahtarı/properties yok. Gerçek signing guard durdu; debug key ile release oluşturulmadı.|
|Güncel APK ile tam native oyuncu zinciri|NOT RUN|Yeni APK native cihaza kurulmadı. V240’daki ilk raster SIGSEGV çözülmüş sayılmaz; sağlıklı Android kabulü gerekir.|
|V240 native raster çökmesi|FAIL|Önceki gerçek API29 logunda SIGSEGV; sonraki sınırlı tekrarlar root cause veya çözüm kanıtı değil.|
|Fiziksel cihaz / FPS / RAM / p95–p99 / gerçek16KB|NOT RUN|Sağlıklı fiziksel cihaz/KVM/GPU yok. Atlas boyutu veya host decode ölçümü bu kapıları kapatmaz.|
|Üretim Firebase / Google / AppCheck / Play Integrity|BLOCKED|Kimlik/erişim yok; deploy yapılmadı. Yerel admin SDK veya mock başarıları gerçek attestation değildir.|
|Play lisans purchase/pending/restore/refund/subscription|BLOCKED|Uygun lisans hesabı/test track/Play Services cihazı yok. Gerçek para harcanmadı.|
|Play versionCode/Console beyanları/Pre-launch/kapalı test|BLOCKED|Console erişimi yok; +19 kullanılabilirliği ve zorunlu şartlar doğrulanmadı. Upload/yayın yapılmadı.|
