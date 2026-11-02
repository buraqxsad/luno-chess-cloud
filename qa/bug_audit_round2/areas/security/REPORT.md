# Security — ikinci bağımsız bug avı

**2 yeni P2 kusuru doğrulandı ve düzeltildi. Son own-fix incelemesinde bu kapsamda açık yeni doğrulanmış kusur:0.** Önceki yedi düzeltme yeniden sayılmadı; evrensel “bug-free” sonucu verilmedi.

| Kusur | Önce | Düzeltme ve son kanıt |
| --- | --- | --- |
| DM moderation report yanlış konuşmanın özel metnini kullanabiliyordu | Geçerli Auth/AppCheck handler ile3PASS/2FAIL; beklenen404 yerine200. Aynı target ile iki farklı valid UID pair aynı legacy key’e çakışır. | Üye haritası declared ise exact iki true participant; yalnız member map ve seçilen message bounded get.6/6PASS; private text client response’a dönmüyordu, hata false moderation/report bütünlüğüdür. |
| Hesap silme user-visible pushed notification’larda raw sender UID/alias bırakıyordu | Gerçek sendFriendRequest→pending veya reject→deleteAccount:0PASS/2FAIL. users/owner silinmiş ve API deleted=true iken recipient notices kalıyordu. | Legacy/orphan recipients dahil5’li SDK-key-order sayfalar; owner-aware notice tx; durable checkpoint, bounded retry;14/14PASS. |

Son gerçek kaynak regresyonu **14 dosyada245/245PASS,0fail,0skip**. Her dosya ayrı doğrudan Node sürecinde çalıştı; dosya seviyeli worker PASS sayısı kullanılmadı. `final-focused-results.json` gerçek TAP count/exit/source hash’lerini saklar. Testler örtüşür; root’un full suite sonucuna ayrıca eklenmez.

Bildirim testleri: gerçek pending/rejected akışı;13orphan recipient ve numeric SDK order ile duplicate recipient okumama; stale-page farklı author replacement’ı koruma; page-query hatası→processing/checkpoint→retry;250recipient invocation-budget tail;610recipient dört+delete attempt ile3/hour initial ve30/min resume ayrımı; checkpoint write öncesi ve committed-but-response-lost hataları; marker sonrası gecikmiş gerçek social delivery cleanup; empty tree; iki rate limit negatif kontrolü; Auth cleanup sürekli hata verirken userdata root cleanup’ın resume budget’ını resetlememesi. Son complete durumunda temporary resume buckets ve raw recipient cursor silinir.

Own-fix review’de ilk resume bucket’ın `serverRateLimits/uid` altında tutulmasının Auth cleanup hatasında resetlenebileceği bulundu; root bunu `accountDeletions/hash(uid)/resumeRate` içine taşıdı. Bu, aynı bildirim-erasure fix’inin doğruluk sınırıdır; üçüncü eski üretim bug’ı diye sayılmadı. Son helper normal ilk girişte3/hour, server-owned processing resume’da30/min uygular. Başka account UID’si veya public RTDB write izni eklenmedi.

Page sayısı bounded; her sayfa en fazla5recipient value taşır.15s/page-budget dolarsa false deleted=true yerine processing+503 kalır, sonraki çağrı checkpoint’ten devam eder. Tek bir recipient’ın çok büyük tarihsel notice value’si için native bellek/latency ölçümü yapılmadı; bu rapor performans kabulü değildir. Tombstone yeni sosyal yazıları engeller, önce başlamış write için mevcut metadata postgate cleanup’ı kanıtlandı.

İncelenen diğer sınırlar: AppCheck Android appID ve production/emulator ayrımı; silme tombstone/migration; Google provider/owned metadata; DM read receipts/committed send proof; sosyal block/friend/deletion callback sıraları. Yeni doğrulanmış başka kaynak kusuru bulunmadı. Üretim Firebase/Google/Play, gerçek Android ve tam regresyon bu ajan tarafından çalıştırılmadı.

Üretim `index.js` dosyasını yalnız root değiştirdi. Ajan iki yeni test dosyası ve dış patch/kanıt hazırladı; commit, deploy, gerçek ödeme veya push yapmadı. Son kaynak SHA ve test SHA’ları `result.json` içindedir. Root’un mevcut native/golden/Play yayın engelleri bu scoped0sonucuyla kapanmaz.
