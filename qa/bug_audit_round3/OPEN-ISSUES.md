# Yayını engelleyen açık sorunlar

| Öncelik / kapı | Somut neden | Durum |
| --- | --- | --- |
| P1 — önceki native raster çökmesi | API 29 profil açılışında `1.raster` / `libflutter.so` / allocator SIGSEGV kaydı var. Sonraki welcome görüntüleri kök neden veya düzelme kanıtı değildir. Bu tur yeni native tekrar yapılmadı. | OPEN / UNRESOLVED |
| Görsel kabul | 97 test referans görüntüsünden farklı. Yeni adaylar eski V239 adaylarıyla aynı; golden referansları incelenip onaylanarak değiştirilmedi. Bu durum yeni üretim hatası diye yeniden sayılmadı; suite başarısız kalır. | FAIL |
| Gerçek Android yolculuğu ve performans | Bu worker’da KVM, donanım GPU veya fiziksel cihaz yok. Yeni APK ile tutorial→maç→online→ödül zinciri, uzun maç, FPS/p95–p99/RAM ve gerçek 16 KB çalışma testi tamamlanmadı. | NOT RUN |
| Güvenlik ve backend servis kabulü | Kaynak ve yerel testler geçti; staging/üretim Auth, App Check, Integrity ve Google hesap kabulü için erişim yok. | BLOCKED |
| Play Billing | Gerçek lisans test hesabı ve Play track yok; pending, restore, iptal, refund ve üyelik senaryoları gerçek Play’de doğrulanmadı. | BLOCKED |
| İmzalı release APK/AAB | Mevcut upload keystore/properties bulunmuyor. Koruma doğru biçimde build’i engelliyor. Yeni anahtar oluşturulmadı. | BLOCKED |
| Play Console | +19’un geçmişte kullanılabilirliği, mağaza beyanları/görselleri, Data Safety, gizlilik ve silme bağlantıları, içerik derecelendirmesi, test hesabı, Pre-launch Report ve kapalı test koşulları doğrulanmadı. | BLOCKED |

Bu tur düzeltmesi yapılan dokuz yeni hata ailesinden açık bırakılan yok. Bu sınırlı sonuç yukarıdaki engelleri kapatmaz. Genel karar **RELEASE HOLD**.
