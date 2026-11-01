# Yerel RTDB takip kanıtı — NOT COMPLETE

**Bu takipten SDK kabulü PASS sonucu çıkarılmadı.** İki ayrı bounded denemede worker35s sınırına ulaştı. İkinci denemede ilk iki vaka12s timeout verdi; bağımsız bağlantıyla tamamlanmış durable observation sayısı0. Hedef backend davranışları bu proof için NOT RUN/INCOMPLETE bırakılır; timeout’lar frozen oyun kodunda yeni kusur diye sayılmaz.

Kesin güncel kaynak: `219b1daf5f2329c558bc1ac7a3cf6c781e316514`. Backend değişiklik commit’i `21dcb5032e43d805431a3cdd24af147f4f6dfc19` ile functions ağacı byte-identical. Index SHA-256 `5b0a8ef98fd05ee3d8414db884b617fdef44881c2c3c27ade8be5fbaa82aaf59`; read-only `git show` ile dış dosyaya alındı ve başarısız koşudan sonra live kaynakla tekrar doğrulandı. Repo/SDK dosyası değiştirilmedi.

Hedefler: (1) confirmed pre-grant refund→suspended currency grant, (2) ON_HOLD→suspended profile grant, (3) ON_HOLD→suspended granted-claim transaction. Google Play yanıtları fake; memoryDatabase fixture yok. Her okuma/yazma gerçek RTDB/Admin SDK yolunu kullanmayı amaçlar, fakat kalıcı assertion sonuna ulaşılmadı.

İlk deneme proxy environment’ını aynen taşırken localhost SDK ilerlemedi; tüm özgün dosyalar `inherited-proxy-timeout/` içinde korunur. Parent’ın açıkça yetkilendirdiği tek tekrarda, SDK yüklenmeden önce `faye-websocket.Client` için ince bir transport adapter eklendi. Yalnız `ws://127.0.0.1:19000/.ws` ve `demo-luno-billing-fence-default-rtdb` namespace’ine izin verir, diğer URL’leri reddeder. Aynı native Client’a URL/protocol/headers ve diğer options aynen aktarılır; yalnız bu kesin loopback için `options.proxy` kaldırılır. HTTP_PROXY/HTTPS_PROXY ve diğer proxy/header environment bağları korunur. Veri veya transaction cevabı uydurulmaz. **Transport değiştirilmeden çalıştırıldı iddiası yoktur.** Adapter’ın after-hook execution audit’i de tamamlanmadığından başarılı native socket seçimi kanıtlanmış sayılmaz.

Yalnız RTDB4.11.2/127.0.0.1:19000/demo namespace başlatıldı. Güncel gerçek rules HTTP200 ile yüklendi. Auth/Functions/Android/production/staging açılmadı. Bu privileged Admin SDK proof’u geçse bile client rules veya lisanslı Play kabulünü göstermezdi.

| Deneme | Süre | Java+Node peak RSS | Sonuç |
| --- | --- | --- | --- |
| İlk inherited-proxy |42.937s|317484KiB|35s worker limit; incomplete|
| Tek exact-loopback adapter tekrarı |42.004s|325136KiB (~317.5MiB)|35s worker limit; incomplete|

Java Xmx192MiB/two CPUs kullanıldı;600MiB RSS sınırı aşılmadı. Her iki denemede Java/Node kapatıldı, port19000 kapalı, private log sayısı0. Ek emulator denemesi yapılmadı. `fixed.log`, `emulator.log`, `run.log`, `results.json`, source ve harness dosyaları kanıtı korur. Mevcut208/208 memory-fixture regresyon ve root tam test sonuçları ayrı kalır; bu denemeler onların pass sayısına eklenmedi.
