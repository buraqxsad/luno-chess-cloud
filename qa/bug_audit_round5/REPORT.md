# Beşinci sistem taraması

**8 somut kusur kapatıldı: 2 yeni P2 aile ve önceki ailelerde 1 P1 + 5 P2 yeni kapsam eksiği.** İki ek yerel SDK başarısızlığı henüz sınıflanmadı; yeni silme entegrasyon kabulü tamamlanmadı. Yeni güvenlik incelemesinin bir bölümü BLOCKED; bütün oyunda hatasızlık kanıtlanmadı. **RELEASE HOLD.**

Alınmış Premium Pass’in eski sezon okumasıyla kaybı; yarım grant sonrası refund; mağaza kataloğu toparlanması; eski pending sahiplik yanıtı; özel kart seçimindeki stale callback; ACK/cleanup; eski V1 geçmişinin silinmesi ve legacy maçların silinmiş veriyi geri yazması düzeltildi. [Sekiz kök neden/commit](BUGS.md) · [Dosyalar](CHANGED-FILES.md) · [Kapsam](scope-clean-status.json).

Tam regresyon ve APK aynı `767ae74314a664f180ad1ca9e279e2c9881989d2` commit’indendir. Kaynak dalı, 24 kart, sanat/atlaslar, V235–V240 düzeltmeleri ve debug imza kimliği korundu. Yeni kart/mod/animasyon altyapısı veya framework yükseltmesi eklenmedi.

| Kontrol | Sonuç |
| --- | --- |
| Flutter analiz | Temiz |
| Tam Flutter/448 dosya | **11881 geçti/97 başarısız/0 atlandı** |
| Backend/104 dosya |1481 geçti/0 başarısız/1 atlandı |
| TypeScript |376/376 |
| Dart/TS differential |3101 senaryo/10967 durum ve tam geçerli hamle kümeleri; 0 ayrışma |
| Yerel gerçek RTDB/Admin SDK | **7 geçti / 2 başarısız**; yeni silme akışları başlangıçta INVALID_ACTION400 ile durdu |

Koşular örtüşür, sayıları toplanmadı. Seçilmiş ekonomi193/193, billing75/75, özel kart34/34, online ACK17/17, tarihsel silme118/118, legacy52/52 ve istemci silme24/24 geçti. Ayarlar/ölçüm izni67/67. Motorun yeni bounded Node30/30 ve host Dart CLI30/30 kontrollerinde yeni kusur doğrulanmadı;6433 Dart assertion/657 final branch. Tek özel başlangıç yerleşiminden 30 iz; bütün erişilebilir durumlar veya bağımsız tam oracle değildir. Bu Dart koşusu Android cihaz testi değildir. [Motor sınırları](areas/rules/REPORT.md).

Tam Flutter’daki97 hata aynı eski pixel karşılaştırmalarıdır ve97 adayın tamamı R4 ile byte-identical. Yeni görsel kabul verilmedi; hiçbir golden değişmedi. **Tam Flutter FAIL.** [Sınıflandırma](evidence/flutter/failure-classification.json) · [Hash karşılaştırması](evidence/flutter/golden-comparison.json). [24 kart matrisi](cards/acceptance.md) · [Dosya/RAM/performance sınırları](cards/performance-limits.json) ve [TR](screenshots/guided-target-tr.png)/[EN](screenshots/guided-target-en.png) görüntüleri gerçek Flutter widget/fixture çıktılarıdır; Android ekran görüntüsü değildir.

Yeni güvenlik ajanının turu otomatik içerik filtresinde olası siber güvenlik riskiyle durdu; probe yalnız file-wrapper/harness failure üretmişti,4 gerçek vaka sonucu yok. Doğrulanmamış scratch dış kanıtta saklandı; yeniden ifade edilip başka ajana verilmedi veya yeni güvenlik PASS sonucu sayılmadı. Mevcut AppCheck12 ve günlük ödül5baseline kontrolü ile tam API/security regresyonları ayrı geçerli sonuçlardır. [Blokaj](areas/security/BLOCKED.json). Online ajan son aşamada model kullanım limitine takıldı; ana ajan verilen minimal istemci patch’ini ve 24/24 normal onaylı yerel testi tamamladı. İlk sandbox/yanlış test yolu/fixture denemeleri kanıtta korunur; bug/PASS sayılmadı.

Yerel SDK gerçek RTDB/Admin transaction’larını ve bağımsız checker bağlantısını kullanır. Auth/App Check/Google yanıtları fake; Admin işlemleri client rules kabulü değildir. Yalnız exactlocalhost/demo namespace için standalone proxy koşulu bellekte değişti; proxy/header/SDKdisk ve DB transaction mantığı korundu. Gerçek Firebase/Google/Play kabulü değildir. [9 vakanın gerçek sonucu: 7 geçti / 2 başarısız](local-sdk-summary.json).

Disk bütçesi için yalnız durmuş emulator snapshot RAM’i geçici kayıpsızgzip olarak saklandı; açılmadı. Test/paket sonrasında orijinal 1426527045 bayt ve SHA256 doğrulanarak geri kondu, geçici arşiv silindi. Oyun asseti/QAfixture veya araç kurulumu silinmedi. [Byte koruma kanıtı](evidence/snapshot-space.json). APK kopyaları erken temizlenerek R4’teki disk taşması tekrar edilmedi; yalnız yeniden üretilebilir ara çıktılar kaldırıldı.

Güncel ARM64 **debug test APK’sı** üretildi: com.luno.chess/1.6.3+19, minSdk 24/targetSdk 36; aynı debug sertifikası,750 asset, ELF/ZIP statik 16 KB. [Paket kimliği/hash/imza](android/apk-verification.json) · [SHA256](APK-SHA256SUMS). Release APK/AAB mevcut upload key eksikliğinde BLOCKED; yeni imza oluşturulmadı.

Önceki native raster çökmesi,97 görsel fark, gerçek cihaz/performans/16KB ve Firebase/Play/Console kabulleri açık. [Kapılar](GATES.md) · [Açık sorunlar](OPEN-ISSUES.md) · [Atlanan/bloke testler](skipped-and-blocked.json). Canlı deploy, gerçek ödeme, Play upload/yayın veya GitHub push yapılmadı. **RELEASE HOLD.**
