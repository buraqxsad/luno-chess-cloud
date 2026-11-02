# Dördüncü sistem taraması

**4 yeni hata ailesi ve önceki düzeltmelerin kapsamadığı 2 yol kapatıldı: toplam 6 somut kusur.** Yeni aileler 1 P1/3 P2, önceki ailelerdeki eksikler 1 P1/1 P2. Bu turda doğrulanıp açık bırakılan yeni kaynak kusuru: 0. Bütün oyunda hatasızlık kanıtlanmadı. **RELEASE HOLD.**

Yarım RTDN bildiriminin kaybolması ve eski worker’ın takeover durumunu ezmesi; kalıcı sanılan recovery yazıları; eski private projection’dan pencere açılması; Türkçe arena başlığında eksik glifler düzeltildi. Oda/davet/legacy rezervasyonları ve compact Pass, önceki ailelerin eksik yolları olarak ayrıca kapatıldı. [Altı kök neden/commit](BUGS.md) · [Dosyalar](CHANGED-FILES.md) · [Kapsam sonucu](scope-clean-status.json) · [Sistem kapsamı](SYSTEM-COVERAGE.md).

Build ve son Flutter kaynağı `0f40ddda041c205b129f3a35d9d4e9f1b661bf8c`. Backend koşusu `e1bdd772c7ce5336c4f0ad4faf3c8b411c15cf42` ile başladı; sonradan yalnız GameStore’daki redundant null guard kaldırıldı. Backend, TypeScript ve Dart motor/runner girdileri final kaynakla byte-identical; [hash/provenance](evidence/backend-scope-provenance.json). Tam Flutter final kaynakta yeniden çalıştı. Önceki düzeltmeler, 24 kart, oyun kuralları, sanat/atlaslar ve imza kimliği korundu.

| Doğrulama | Sonuç |
| --- | --- |
| Analiz | Hata/uyarı yok |
| Tam Flutter, 445 dosya | **11862 geçti /97 başarısız /0 atlandı** |
| Tam backend, 99 dosya | 1458 geçti /0 başarısız /1 atlandı |
| Tam TypeScript | 376 geçti /0 başarısız /0 atlandı |
| Dart/TS differential | 3101 senaryo / 10967 durum ve tam geçerli hamle kümeleri; 0 ayrışma |
| Yerel gerçek RTDB/Admin SDK | 7/7: Billing/lease 6 + legacy recovery 1; bağımsız SDK kalıcı veriyi doğruladı |

Koşular örtüşür, sayıları toplanmadı. Node dosyaları doğrudan gerçek TAP vakalarıyla çalıştırıldı. [Flutter](flutter-summary.json) · [Backend](backend-summary.json) · [TS](typescript-summary.json) · [Atlanan opt-in test](skipped-tests.json). [Diferansiyel kaynak kanıtı](evidence/differential/source-provenance.json).

97 görsel FAIL’ın tamamı ayrıca görsel olarak incelendi; eski render/font ortamı ve eksik tasarım onayı genel kabulü engelliyor. 96 aday V239 ile aynı baytlar; promotion adayı kanıtlanmış Türkçe font düzeltmesi nedeniyle değişti. Önceki üçüncü tur adayı ile fark yalnız (99,91)–(291,126) başlık bölgesinde 2045 piksel. Önce/sonra raster ve tam ekranlar ayrıca incelendi; paketleme yalnız bu exact PNG hash’ini tanır. **Hiçbir golden güncellenmedi; tam Flutter FAIL.** [97-case inceleme](areas/visual/MATRIX.md) · [Glif düzeltmesi](areas/visual/PROMOTION-FIX.md) · [Onaylanan tek aday hash](evidence/approved-visual-candidates.json) · [Son karşılaştırma](evidence/flutter/golden-comparison.json).

[24 kart matrisi](cards/acceptance.md) gerçek Flutter savaş ekranı/fixture kapsamıdır; native Android değildir. [TR](screenshots/guided-target-tr.png) ve [EN](screenshots/guided-target-en.png) widget çıktılarıdır. Yeni rule probları iki dilde 78.464 assertion ve her dönüşümde 4.775 olası sonraki hamleyi kontrol etti; yeni motor kusuru doğrulanmadı. Bu bağımsız tam oracle değildir. [Sınırlar](areas/rules/REPORT.md). Atlas dosyaları toplam 585174 bayt; son host testi 9 MiB RGBA boyutunu doğruladı. Bu Android RAM/GPU ölçümü değildir. [Performans sınırları](cards/performance-limits.json).

Seçilmiş GameStore 119/119, savaş 122/122, ekonomi 84/84, online 62/62 ve font/ilerleme 39/39 geçti; bunlar tam koşularla örtüşür. Ajanın son client validation isteği approval-service kullanım limitinde çalıştırılamadı; parent’ın ayrı normal incelenmiş isteği exact baseline replay ve 119/119’ı tamamladı. Onay atlanmadı. Online agent içerik flag’i sonrası root mevcut yerel pozitif/kurtarma testlerini ve minimal düzeltmeyi tamamladı. İlk hatalı font-path/fake-async raster denemeleri, fixture hatası ve ilk analyze uyarısı kanıtta korunur; bug veya PASS diye sayılmadı. [Client raporu](areas/client/REPORT.md) · [Online raporu](areas/online/REPORT.md).

Yerel SDK gerçek RTDB/Admin transaction’larıdır; Google yanıtları fake’tir, gerçek Auth/App Check/Play/production kabulü değildir. Tek exact localhost/demo namespace için standalone transport proxy koşulu bellekte değişti; SDK disk/proxy ortamı/header’lar korundu. [Yedi vaka](billing-sdk-summary.json). JVM/Node RAM ölçümü Android RAM’i değildir.

İlk APK derlemesi exit 0 ile tamamlandı. Disk doluluğu ilk paket denetimini klasör oluşturmada durdurdu; o denetimde hiçbir kontrol PASS sayılmadı. Tam APK SHA/ZIP CRC ile doğrulanıp aynı baytlarla korundu; yalnız byte-identical kopyalar ve tamamlanmış derleme ara çıktıları temizlendi. Derleme tekrarlanmadan aynı APK yeniden denetlendi. [Başarısızlık ve kurtarma](evidence/android/package-audit-recovery.json), [ilk komutlar](evidence/android/initial-package-audit/commands.json).

Güncel **ARM64 debug test APK’sı**: com.luno.chess / 1.6.3+19, minSdk 24/targetSdk 36; aynı debug sertifikası, 750 asset, ELF/ZIP statik 16 KB. [Paket kanıtı](android/apk-verification.json) · [SHA256](APK-SHA256SUMS). Release APK/AAB upload key eksikliğinde BLOCKED; yeni imza oluşturulmadı.

Önceki native raster SIGSEGV açık; yeni APK native cihazda oynatılmadı. Fiziksel FPS/RAM/p95–p99/uzun maç ve gerçek 16 KB çalışması yok. Üretim Firebase/Google/App Check/Integrity, Play lisans ve Console kabulü tamamlanmadı. [Kapılar](GATES.md) · [Açık sorunlar](OPEN-ISSUES.md). Canlı deploy, para, Play upload/yayın ve GitHub push yapılmadı. **RELEASE HOLD.**
