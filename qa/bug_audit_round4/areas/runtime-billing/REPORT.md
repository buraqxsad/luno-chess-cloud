# Son gerçek yerel RTDB/Admin SDK kontrolü

Son sabit kaynakta **7/7** vaka geçti: 6 Billing/lease, 1 eski friendly rezervasyon kurtarma. Ayrı SDK bağlantısı kalıcı veriyi okudu.

- `pregrant-refund`
- `stale-subscription-profile-grant`
- `stale-subscription-granted-claim`
- `fresh-owned-inactive-without-rtdn`
- `first-inapp-ACKed-unmatched-refund`
- `interrupted-RTDN-lease-retry`
- `legacy-friendly-reservation-recovery`

Kaynak `0f40ddda041c205b129f3a35d9d4e9f1b661bf8c`; index SHA-256 `92c1fe742398d30255e33efffc78e82aa6cc862f6a11e7955cc2444b48920a08`. [Ham sonuç ve gözlemler](results.json), [TAP](fixed.log.gz), [taşıma koşulu](transport-provenance.json).

RTDB 4.11.2 ve gerçek Admin SDK kullanıldı. Google/Play yanıtları fake; gerçek Auth/App Check/Functions trigger/Play testi yok. Admin işlemleri istemci güvenlik kurallarını atlar; kuralların yüklenmesi istemci rule kabulü sayılmadı. Yalnız kesin localhost/demo namespace için bundled standalone transport içindeki tek proxy seçimi koşulu bellekte değişti. SDK disk dosyası, proxy ortamı, header ve transaction kodu korunur. Dış endpoint’e bağlanma reddedilir.

Bütün süreç sınırlı süre/RAM içinde çalıştı, worker ve JVM kapatıldı, 19000 portu serbest bırakıldı; özel log kalmadı. Host JVM/Node RSS ölçümü Android RAM veya performans sonucu değildir. Gerçek Firebase/Play kabulü **BLOCKED**.
