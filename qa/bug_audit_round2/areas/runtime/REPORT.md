# İkinci runtime incelemesi

**İncelenen kaynak kapsamında yeni doğrulanmış oyun kodu kusuru: 0.** Bu sonuç bütün oyunda hata bulunmadığı veya native yayının kabul edildiği anlamına gelmez. Önceki API29 raster çökmesi açık kalır.

## Yerel Billing SDK kabul boşluğu

Önceki iki timeout'un ikinci denemesindeki adapter yanlış constructor'a uygulanmıştı. `firebase-admin/lib/database/database.js`, `@firebase/database-compat/standalone` modülünü yükler. Bu dosya faye istemcisini kendi bundle'ına alır (`Client`, `WebSocket$1.Client`, `Websocket`, `setWebSocketImpl(Websocket.Client)`). Dış `require('faye-websocket').Client` değişikliği gerçek Admin SDK transport'una ulaşmaz.

Emulator başlatmadan yapılan module-loader probe bunu doğruladı: Admin yolu standalone modülünü yükledi; dış `faye-websocket` yükleme sayısı **0**. Probe herhangi bir database okuması/yazması yapmadı. `module-loader-result.json` ve `module-loader.log` bu teşhis kapsamını korur. Bu, yeni üretim oyun bug'ı olarak sayılmadı; önceki QA harness adapter'ının kusurudur.

Root'un açık yetkisiyle tek bounded yerel koşu yapıldı. Repo ve SDK disk dosyaları değiştirilmedi. Gerçek standalone modülün in-memory kopyasında sadece proxy-selection koşuluna, kesin `ws://127.0.0.1:19000/.ws` ve `demo-luno-billing-fence-r2-default-rtdb` namespace'i için istisna eklendi. Diğer socket URL'leri reddedilir. HTTP_PROXY/HTTPS_PROXY dahil environment ve header kodu korunur; tüm okuma/yazma/transaction uygulaması aynı kalır. `sdk-proof/standalone-transport.patch`, orijinal/in-memory hash'ler ve `transport-audit.json` bu sınırı açıkça gösterir. **Değiştirilmemiş transport ile test edildi iddiası yoktur.**

Önce üç saniye sınırındaki gerçek SDK seed/read smoke geçti. Ardından gerçek exported backend fonksiyonları, Firebase Admin SDK14.2.0 ve RTDB4.11.2 ile **3/3 PASS**, sıfır fail/skip verdi. Google Play provider yanıtları fake; memoryDatabase fixture kullanılmadı. Ayrı bir SDK bağlantısı kalıcı veriyi doğruladı:

| Gerçek SDK senaryosu | Kalıcı gözlem |
| --- | --- |
| Confirmed refund → bekleyen profile grant | Gold1250 olarak kaldı; ungranted marker var; purchase receipt yok; consume çağrısı0; `purchase-revoked` |
| Yeni ON_HOLD → bekleyen profile grant | Premium0; claim inactive; claim revision2 ve profile fence2; yeni claim değişmedi; retriable503 |
| Yeni ON_HOLD → bekleyen granted-claim write | Premium0; claim inactive; revision2=fence2; yeni claim birebir korundu; retriable503 |

Captured kaynak commit'i `219b1daf5f2329c558bc1ac7a3cf6c781e316514`, index SHA-256 `5b0a8ef98fd05ee3d8414db884b617fdef44881c2c3c27ade8be5fbaa82aaf59`; bu dosya round2 başlangıcı `b1b9c7a2f76282c6588383d5ab7926ec8b438e5f` ile byte-identical. Başlangıç ve koşu sonunda source eşitliği yeniden doğrulandı. Bu dar yerel SDK kanıtı önceki eksik kabulü üç hedef vaka için kapatır; sonraki farklı source değişikliklerine otomatik PASS vermez.

Toplam11.311s; Java+Node peak347592KiB (~339.4MiB),600MiB sınırı altında. Java Xmx192MiB/two CPUs; yalnız tek demo RTDB çalıştı. İki gerçek SDK socket seçimi kaydedildi. Sonunda Java/Node kapatıldı, port19000 kapalı, private log sayısı0. Önceki iki başarısız koşu `/workspace/luno-review/system-bug-hunt/economy/sdk-proof/` altında korunur; başarı sayılarına katılmadı.

## Android/native kapsamı

Filtrelenmiş eski trace, `1.raster` thread'inde null pointer SIGSEGV gösterir. Üst frame'ler libc `extent_recycle`/`je_malloc`, ardından `libflutter.so` içindedir. Öncesinde Impeller/EGL tanı mesajı vardır; bu mesaj tek başına kök neden kanıtı değildir. Trace'te bir Dart kaynak frame'i veya Luno özel JNI işlevi gösterilmez.

Android manifest, `MainActivity.kt`, Gradle signing/SDK yapılandırması, Flutter main ve loading handoff kaynağı incelendi. MainActivity yalnız package metadata ve sınırlı legal-link platform kanallarını kurar; mevcut trace'i bu koddan türeten somut tekrar üretim bulunmadı. Donanım hızlandırma, SDK, shader veya renderer ayarı değiştirilmedi.

Önceki V239/V240 default açılışları aynı Flutter engine hash'iyle90s sonunda welcome1/3 çizmişti. Bu sınırlı retry, ilk çökmenin giderildiğini kanıtlamaz. Bu ajan yeni Android emulator açmadı, uygulama kurmadı, fiziksel cihaz veya16KB runtime çalıştırmadı. FPS/RAM/p95–p99 ölçümü üretilmedi.

Üretim Firebase/Auth/AppCheck/Play Integrity, gerçek Play lisans ödeme senaryoları ve Console kabulü **BLOCKED/NOT RUN** kalır. Gerçek Google account veya ödeme/deploy/upload/push yapılmadı. **RELEASE HOLD korunur.**

## Final kaynak takip doğrulaması

Son commit `9d41c5055006907ee2dafdf8e5daf70bb9f2c7a3` /index `5c6800410e05ff020a8e576b67b2419eaad5f56f44a912d8d48ceace7c85b486` üzerinde dört gerçek yerel SDK vakası: **PASS**, `{'tests': 4, 'pass': 4, 'fail': 0, 'skipped': 0, 'cancelled': 0}`. Yeni dördüncü vaka önce owned active grant, sonra RTDN olmadan fresh ON_HOLD→inactive claim/Premium0/private fence eşitliğini doğrular. Ayrı SDK bağlantısı kalıcı veriyi okur. Önceki3PASS ile örtüşür; sayılar toplanmaz. [Final kapsam ve kanıt](sdk-proof-final/REPORT.md). Disk SDK/repo değişmedi; üretim/Play/native kabulleri açık kalır.
