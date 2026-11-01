# Açık yayın engelleri ve kabul boşlukları

| Sınıf | Açık durum | Somut neden / ihtiyaç |
| --- | --- | --- |
| P1, önceki native hata | V240 ilk API29 profile açılışında raster SIGSEGV | Native allocator/libflutter izi kaydedildi; sağlıklı gerçek Android'de kök neden ve düzeltme kanıtı yok. Yeni debug APK bunu doğrulamadı. |
| P1 kabul boşluğu | Tam native oyuncu yolculuğu ve fiziksel performans | VM'de KVM/GPU yok; önceki ANR/etkileşim problemi. Yeni Flutter widget PASS'leri cihaz/FPS/p95–p99/RAM kabulü değildir. |
| P1 görsel kabul boşluğu | 97 tarihsel golden farkı | Yeni koşuda referanslar korunur; eski adaylarla karşılaştırma ayrı kaydedilir. Önceki tasarım onayı/QA girdileri aktarımda eksik; gelişi güzel golden güncellenmedi. |
| Entegrasyon kabulü | Yeni Billing gerçek SDK proof'u tamamlanmadı | İki bounded koşu timeout;0 durable gözlem. Mock/fake port testleri bu kapıyı kapatmaz. |
| Yayın anahtarı | Release APK/AAB BLOCKED | Mevcut upload key/properties yok; imza kimliği değiştirilmedi. |
| Dış servis kabulü | Firebase/AppCheck/Google/Integrity ve Play lisans/Console BLOCKED | Yetkili üretim/staging/lisans hesabı/testtrack/Console erişimi yok. Canlı deploy/ödeme/upload yapılmadı. |

Bu listede kanıtlanmamış bir P0 açığı varmış gibi iddia edilmedi. Kaynak avında yeni tespit edilen7hata kapatıldı; kapsam dışı veya çalıştırılamayan kabuller başarılı sayılmadı. **RELEASE HOLD.**
