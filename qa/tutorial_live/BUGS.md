# Düzeltilen doğrulanmış kusurlar

**2 üretim P1 ve 1 üretim P2 kusuru** düzeltildi; V240’taki eski kusurlar yeniden sayılmadı.

| Kusur | Kök neden ve düzeltme | Commit ve kanıt |
| --- | --- | --- |
| Premium hakkının yarışla silinmesi / geri açılması | Claim snapshot’ı user transaction dışında eski kalabiliyordu. Profil revision eşleşmezse claim yeniden okunur; üç çatışmada stale yazım/publish yerine retriable503. Claim yetkisi/refund korunur. | d07e7b4;12 yeni regresyon. Gerçek RTDN handler, failed event’in yeniden alınması ve duplicate sırası test edildi. |
| Eski makbuz yeni satın alma kilidini çözüyordu | Idempotency kontrolünden önce global launch kilidi kaldırılıyordu; restore ayrıca geç native Future’ı yanlış tamamlayabiliyordu. Tarihsel token replay kilidi sahiplenmez, yalnız aynı gerçek işlem/timeout kilidi çözer. | d1f89ff;3 adversarial yarış +3 kontrol, ilgili61/61 geçti. |

P2: Oynanamayan/discard-only kartın tahtaya dokunması `invalidTarget` üretip imkânsız hedef istiyordu; boş elde rehber kart seçimini vurguluyordu. Geçerli Play hedefi yoksa seçim feda için korunur, yanlış kare hatası üretilmez; başlık availability kontrolünü kullanır. Boş elde Kartı Geç ve gerekiyorsa yeniden başlatma açıklanır. Önce6pass/5fail, sonra22 özellik +8 güvenlik +12 mevcut etkileşim:42/42 PASS. Commit: dbdc074.

Dosyalar: `luno_chess/lib/battle_ui/interaction.dart`, `luno_chess/lib/battle_ui/practice_coach.dart`, `functions/index.js`, `functions/test/subscription-reconciliation-race.test.js`, `luno_chess/lib/services/luno_billing_service.dart`, `luno_chess/test/billing_historical_receipt_launch_test.dart`.

Yeni tutorial teslim öncesi incelemesinde, aynı-cue parent rebuild’inin idle hareketini süresiz ertelemesi ve başlığın kapalı olmayan kart/special move/bitmiş deneme ile uyuşmaması da bulundu. Yedi failing feature kontrolünden sonra düzeltildi; bunlar eski üretimde bulunan ek kusurlar diye sayılmadı. Son22 özellik testi geçti. Geçerli assertion silinmedi veya zayıflatılmadı.
