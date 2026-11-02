# Son kaynak — yerel Billing SDK

Kaynak `8b12d5aa649d26b1eb67dd1252922fea53532bbd`; index SHA-256 `c370ab3286f08549122050ce83213542dfd1b52ba582eb2c6389098067cd4f31`.
Gerçek Admin SDK14.2.0 / RTDB4.11.2 ile **5/5 geçti**,0fail/skip. Önceki dört grant/refund/subscription yarışı yeniden doğrulandı. Yeni beşinci vaka first consumable lookup’u claim oluşmadan bekletir; gerçek exported RTDN handler’ı unknown-owner refund’u ACK eder. Sonra eski PURCHASED sonucu döner; registration sonrası güncel Google fake cevabı CANCELED olduğundan altın/makbuz/consume oluşmaz. Ayrı SDK bağlantısı event=complete, unmatched=awaiting-client-claim, gold=1250 ve receipt yok durumunu doğrular; event redelivery duplicate=true kalır.

Google Play yanıtları fake’tir. Auth/App Check/Google/Play lisans veya üretim kabulü değildir. Tek kesin localhost/demo namespace için standalone transport proxy seçimi koşulu bellekte değişti; tüm transaction kodu, SDK disk dosyaları, proxy ortamı ve header’lar korundu. Orijinal SDK hash’i ve frozen index sonunda yeniden doğrulandı.14.6s, birleşik Java+Node peak357100KiB; port19000 kapanmış, private log0. Bu RAM ölçümü Android cihaz RAM’i değildir.

Aynı beş-vaka betiğinin ilk koşusu Android derlemesiyle eşzamanlı çalışırken35s sınırında tamamlanamadı;0tamamlanmış test/0gözlem, FAIL/NOT COMPLETE. Kesin neden belirlenmedi. İlk log/result dosyaları `attempt1/` içinde korunur. Gradle durduktan sonraki seri koşuda aynı kod, assertion ve süre sınırıyla5/5 geçti. İlk hata başarı diye yeniden yazılmadı.
