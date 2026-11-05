# Sekiz somut düzeltme

2 yeni P2 aile; önceki ailelerde 1 P1 + 5 P2 kapsam eksiği. Toplam 8 kusur, 1 P1 + 7 P2. Callback/tekrar deneme alt vakaları ayrı bug olarak çoğaltılmadı.

| Önem | Tür | Kusur | Commit | Düzeltme | Kanıt |
| --- | --- | --- | --- | --- | --- |
| P1 | Önceki ailede yeni yol | [Gecikmiş sezon okuması alınmış Premium Pass’i siliyordu](areas/economy/REPORT.md) | `67c99b8` | Transaction denemesinde güncel saat okunur; geçerli daha yeni sezon Pass’i eski normalizer çağrısından korunur. | 7 baseline:4 geçti/3 başarısız →7/7; ilgili193 koşusunda. |
| P2 | Önceki ailede yeni yol | [Yarım grant sonrası doğrulanmış refund tamamlanamıyordu](areas/economy/REPORT.md) | `1a32a99` | Reconcile-required claim için de grant öncesi iade işareti yazılır. Complete/granted ve eksik receipt korumaları korunur. | 4 baseline:2 geçti/2 başarısız →4/4; ilgili193 koşusunda. |
| P2 | Yeni aile | [İlk ürün kataloğu hatası mağazayı kalıcı kilitliyordu](areas/client/REPORT.md) | `91863e3` | Start ve restore boş kataloğu tekrar sorgular; katalog arızası eldeki satın alma sahipliği kurtarmasını engellemez. | Birleşik9 baseline:4 geçti/5 başarısız; son9/9, ilgili75/75. |
| P2 | Önceki ailede yeni yol | [Eski pending yanıtı doğrulanmış ürünü yeniden beklemeye alıyordu](areas/client/REPORT.md) | `91863e3` | Sorgu başındaki ürün nesliyle güncel canlı durum karşılaştırılır; tokeni boş eski pending de yeni sonucu ezemez. | Yukarıdaki9 ve75 koşularında; ayrı hata diye iki token varyantı sayılmadı. |
| P2 | Önceki ailede yeni yol | [Özel kart penceresinde eski satır yanlış kartı işliyordu](areas/battle/REPORT.md) | `2b2ad1e` | Satırlar mutable indeks yerine CardId tutar; Confirm yalnız boyanmış seçim anahtarı hâlâ geçerliyken uygulanır. | 7 baseline:3 geçti/4 başarısız →7/7; ilgili34/34. |
| P2 | Yeni aile | [Onaylanan sonuç geç cleanup ile yeniden görünüyordu](areas/online/REPORT.md) | `b315685` | ACK aynı transaction’da yalnız eşleşen active ve lastMatch işaretlerini temizler; peer/yeni maç korunur. | 3 baseline:2 geçti/1 başarısız →3/3; ilgili17/17. |
| P2 | Önceki ailede yeni yol | [Eski V1 maçlarda silinen hesabın verisi kalıyordu](areas/online/REPORT.md) | `60fe952` | Sayfalı ve kaldığı yerden devam eden geçmiş temizliği; yarım publish tekrarında sayfa atlanmaz. İstemci503 doğru ilerleme hatasını korur. | Genişleyen5 baseline:1 geçti/4 başarısız; son6/6, ilgili118/118. İstemci3 baseline2/1 →3/3, ilgili24/24. |
| P2 | Önceki ailede yeni yol | [Eski maç sonucu silinen özel kayıtları yeniden yazıyordu](areas/online/REPORT.md) | `767ae74` | Her katılımcı yayını mevcut metadata kontrolünden geçer; geç worker temizliği yeni maç işaretlerini ve yaşayan peer’i korur. | 3 baseline:1 geçti/2 başarısız →3/3; ilgili52/52. |
