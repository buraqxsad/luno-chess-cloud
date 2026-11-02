# İkinci ekonomi taraması — 1 yeni P1 düzeltildi

**Mevcut owned subscription için güncel inactive Google yanıtı eski aktif hakkı koruyordu.** RTDN gelmeden restore/verify çağrısı ON_HOLD veya EXPIRED gördüğünde yalnız `purchase-not-active` dönüyor, global claim active=true ve profile Premium gelecekte kalıyordu. Bu, önceki stale-response yarışından farklı: bu defa güncel ve doğru provider kararı hiç uygulanmıyordu.

Canonical `b1b9c7a` kaynağıyla aynı8vaka **3 PASS /5 FAIL**; yeni patch candidate8/8, root tarafından uygulanmış gerçek kaynakta yeni8/8. Önceki subscription20, refund10 ve Premium recompute12 ile toplam **4 dosyada50 PASS /0 FAIL /0 SKIP**. `focused-results.json` gerçek TAP dosya sonuçlarını içerir; örtüşen koşular toplanmadı.

Düzeltme yalnız önceden owned subscription için inactive yanıtın owner/product kontrolünden geçmesine izin verir. Ardından aynı claimRevision CAS ile inactive lifecycle yazılır ve claim’lerden profil yeniden hesaplanır; çağrı yine `purchase-not-active` döner. Yeni/unowned inactive token claim oluşturmaz. Wrong provider account hiçbir claim/profile alanını değiştirmez. Başka aktif token Premium’u korur. Yeni inactive doğrulama eski ACTIVE profile grant’ini fence eder; gecikmiş eski inactive cevap daha yeni geçerli renewal’ı geri alamaz. Beklenen inactive sonuç generic failure/reconcile-required metadata’sıyla kirletilmez; silme kapısı korunur.

Ajan `functions/index.js` dosyasını düzenlemedi. `inactive-reconciliation.patch` root tarafından uygulandı. Yalnız yeni `functions/test/round2-economy-subscription-inactive-refresh.test.js` eklendi. Önceki assertion/golden silinmedi veya gevşetilmedi. `result.json` baseline/candidate/actual kaynak ve test hash’lerini, kesin kapsamı saklar. Ek finansal debt/refund denklemleri ve günlük cursor/replay kaynakları incelendi; başka yeni doğrulanmış kusur bulunmadı.

**Bu düzeltmeden sonra taranan ekonomi sınırlarında başka doğrulanmış bug yok.** Bu evrensel bug-free veya yayın kabulü değildir. Google Play yanıtları fake ve DB fixture’dır; gerçek Firebase/Play/Android kontrolleri çalıştırılmadı. Canlı deploy, para, upload, push veya commit yapılmadı.
