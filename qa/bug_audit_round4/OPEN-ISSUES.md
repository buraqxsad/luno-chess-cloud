# Yayını engelleyen açık sorunlar

| Öncelik / kapı | Somut neden | Durum |
| --- | --- | --- |
| P1 — önceki native raster çökmesi | API 29 profil açılışında raster/libflutter.so/allocator SIGSEGV kaydı var. Bu tur sağlıklı native ortamda tekrar üretim veya kök nedenin kapandığına dair kanıt yok. | OPEN / UNRESOLVED |
| Görsel kabul | 97 referans karşılaştırması başarısız. Bütün çiftler incelendi; 96 aday V239 ile aynı, yalnız promotion başlığının kanıtlanmış Türkçe font düzeltmesi değişti. Eski render/font ortamı ve bazı tasarım onayları eksik. Golden değiştirilmedi. | FAIL |
| Gerçek Android yolculuğu ve performans | KVM, donanım GPU veya fiziksel cihaz yok. Yeni APK ile tutorial→maç→online→ödül zinciri, uzun maç, FPS/build-raster p95–p99/RAM ve gerçek 16 KB çalışma testi yapılmadı. | NOT RUN |
| Güvenlik ve backend servis kabulü | Kaynak, sahte bağımlılıklı regresyon ve dar yerel SDK kontrolleri geçti. Staging/üretim Auth, App Check, Integrity ve gerçek Google hesap kabulü için erişim yok. | BLOCKED |
| Play Billing | Lisans test hesabı ve Play track yok. Pending, restore, iptal, refund ve üyelik gerçek Play üzerinde doğrulanmadı. | BLOCKED |
| İmzalı release APK/AAB | Mevcut upload keystore/properties yok; imzalama koruması derlemeyi durduruyor. Yeni anahtar oluşturulmadı. | BLOCKED |
| Play Console | +19 uygunluğu; mağaza metin/görselleri, Data Safety, gizlilik ve hesap silme bağlantıları, içerik derecelendirmesi, test hesabı, Pre-launch Report ve kapalı test koşulları doğrulanmadı. | BLOCKED |

Bu turdaki 4 yeni aile ve önceki düzeltmelerdeki 2 kapsam eksiği kapatıldı. Bu sınırlı sonuç yukarıdaki engelleri kapatmaz. Genel karar **RELEASE HOLD**.
