# Ekonomi ve Play bug avı — son kaynak

**2 yeni P1 kusur ailesi düzeltildi.** Önceki canlı Luno teslimindeki Premium snapshot ve purchase-launch düzeltmeleri yeniden sayılmadı. Yeni subscription alt yarışları ayrı bug diye şişirilmedi.

| Kusur | Önce | Son durum |
| --- | --- | --- |
| Onaylanmış iade sonrası bekleyen altın yüklemesi | İlk 5 regresyonda 2 pass / 3 fail; confirmed refund sonrası gold1250→2250 kalabiliyordu | 10/10 yeni test: kalıcı sıfır tutarlı reversal marker aynı profil transaction’ında yazılır; para/borç uydurulmaz, eski grant reddedilir |
| Eski subscription işlemi yeni lifecycle’ı geri açıyor / yayınlanan grant kaybolabiliyor | İlk 4 cold/warm, grant/claim gecikmesi regresyonunun tamamı FAIL | 20/20 yeni test: claimRevision CAS + token profile fence + fresh lookup + final completion CAS |

Son dar kapsam doğrudan Node koşusu: **10 dosyada 208 pass / 0 fail / 0 skip**. Dosya bazlı wrapper PASS, assertion kabulü diye sayılmadı. `final-focused-results.json` her gerçek TAP dosyasının sayısını ve çıkış kodunu içerir. Örtüşen testler root’un tam regresyonuna ayrıca eklenmez.

Subscription sırası: Google owner/product doğrulanır → global claim kayıt olur → ilk kayıtta güncel provider tekrar okunur → profil grant’i ve versioned claim yazılır → claim’ler profile yansıtılır → son complete CAS aynı token revision’ını ve hesap silme kapılarını doğrular. Eski ACTIVE, ON_HOLD’u yeniden açamaz; eski ON_HOLD daha yeni gerçek renewal’ı silemez. Başka aktif token Premium’u korusa bile askıya alınmış satın alma için başarı dönülmez. Profile fence premium zaten0/receipt yokken de kalıcıdır; eski query daha düşük fence ile erişim uygulamadan yeniden okunur.

20 subscription vakası; iki ana gecikme ×cold/warm, zero-access marker, legacy hold→valid recovery, iki yönde stale RTDN, ilk unmatched notification, başka owner ve global claim yokluğu, late acknowledge, ilk revalidation sırasında silme, legacy revision0 record’un authoritative kaybolması, pozitif cold-cache legacy, grant→claim publication gap, final projection’da ON_HOLD, marker rollback, başka active token ve son complete transaction’da ON_HOLD/erasure kapsar. Son claim tamamlaması projection’dan sonradır; plain final read ile yeni stale-snapshot penceresi eklenmez.

Geçerli assertion silinmedi/gevşetilmedi. `retained-record-race.test.js` tam profile deepEqual’ı yalnız yeni beklenen sıfır revocation metadata ve timestamp’ını içerir; unrelated currency/entitlement alanları aynı kalır. İlk subscription2 providercheck +replay1 açıkça3 diye doğrulanır. Eski membership refresh testi artık initial heldquery +completion projection +zorunlu retry toplam3query bekler; entitlement ve stale snapshot reddi assertion’ları korunur.

Dosyalar: `functions/index.js`, `functions/test/retained-record-race.test.js`, `functions/test/subscription-reconciliation-race.test.js`, iki yeni `functions/test/system-hunt-economy-*.test.js`. `result.json` kesin SHA’ları içerir. Agent commit yapmadı; çalışma kodu freeze için hazırdır.

Bu kanıtlar gerçek exported backend fonksiyonları +memory DB fixture +mock Google Play yanıtlarıdır. Gerçek Firebase/Play lisans veya fiziksel Android kabulü değildir. Canlı deploy, gerçek para, Play upload veya kamu yayını yapılmadı. Root’un tam regresyonu ve RELEASE HOLD kapıları ayrıca geçerlidir.
