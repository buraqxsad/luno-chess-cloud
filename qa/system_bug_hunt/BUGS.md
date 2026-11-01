# Bu avda kapatılan yeni kusurlar

**7 yeni hata ailesi: 3 P1 +4 P2.** Önceki tutorial/Premium/receipt düzeltmeleri yeniden sayılmadı. Aynı subscription koordinasyon sorununun alt yarışları ayrı bug diye şişirilmedi.

| Önem | Hata ve kök neden | Düzeltme / önce-sonra kanıtı |
| --- | --- | --- |
| P1 | Refund tamamlanırken daha önce doğrulanmış fulfillment user transaction’ında bekleyip sonradan altın basabiliyordu. | Aynı profile transaction’da sıfır tutarlı durable reversal marker; ilişkisiz bakiye/debt/üyelik değişmez, eski grant reddedilir. [Ekonomi](areas/economy/REPORT.md) |
| P1 | Eski subscription provider yanıtı daha yeni ON_HOLD sonrası profile veya global claim’i yeniden açabiliyordu; profile/claim yayın aralığı da geçerli hakkı silebiliyordu. | Claim CAS + kalıcı token revision marker; late catch/complete guard; ilk sahiplik sonrası tekrar doğrulama; son authority sync ve hedef token başarı kontrolü. Geçerli renewal/legacy/cold cache/silme korunur. [Ekonomi](areas/economy/REPORT.md) |
| P1 | İlk80 hatalı pending settlement kaydı, daha sonraki sağlıklı maçın sonuç/ödülünü süresiz bekletiyordu. | Ayrı rotating settlement cursor ve wrap; bounded80 query. Önce1pass/2fail, sonra3/3; idempotent sonuç. [Online](areas/online/REPORT.md) |
| P2 | Süresi geçen ranked queue, arkadaş odası açıldıktan sonra guest’i OPPONENT_BUSY ile engelliyordu. | Transaction içinde expired queue temizliği; TTL sınırları ve canlı queue koruması. Önce2pass/3fail, sonra5/5. [Online](areas/online/REPORT.md) |
| P2 | Silinen hesabın eski token/heartbeat/onDisconnect işlemi presence’ı yeniden yaratabiliyordu. | Aktif rules, mevcut owner profili gerektirir. Gerçek local RTDB önce9pass/3fail, sonra12/12; ekonomiye/profil yetkisine geçiş iddiası yok. [Kimlik](areas/identity/REPORT.md) |
| P2 | refreshState, yerel username kaydı await’inden sonra başka hesabın hata/sync durumunu değiştirebiliyor ve disposed notifier’ı çağırabiliyordu. | Owner/generation/epoch/access guard await ve senkron store callback sonrası yinelenir. Önce1pass/4fail; yeni7/7 ve ilgili91/91. [Client](areas/client/REPORT.md) |
| P2 | Match version/terminal değişimi, henüz çizilmeyen veya açık modalda eski private seçenekleri bir kare gösterebiliyordu. | Builder admission snapshot ve match listenable; eski child çizilmeden gizlenir. Önce1pass/4fail, yeni5/5, ilgili22/22. [Battle](areas/battle/REPORT.md) |

Kurallar ajanı yeni kusur bulmadı: 48 deterministik maç /8654 state /24 kart korunum kontrolleri, ayrı input-immutability taraması; Flutter488/488. Bunlar bağımsız tam satranç doğruluğu veya gerçek Android kabulü değildir. [Kapsam](areas/rules/REPORT.md).
