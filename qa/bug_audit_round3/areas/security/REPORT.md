# Üçüncü tur — davet ve hesap silme

**1 yeni P2 düzeltildi.** Gerçek handler ile gönderilmiş V1 daveti, gönderen veya alıcı hesabın tamamlanan silme işleminin ardından control/inbox kayıtlarını yeniden yazabiliyordu. Yanıtın sonradan reddedilmesi yan etkiyi temizlemiyordu; silinen alıcıya gönderim 200 de dönebiliyordu. Bu, önceki enqueue/createRoom admission ve notification erasure yollarından ayrı bir route eksikliğidir.

Geçerli tekrar üretim **12 vaka: 8 geçti / 4 başarısız**. Dört send yarışı: sender/recipient × control/inbox yazısı. Altı warm-cache respond acceptance erasure sınırı zaten geçiyordu; ek bug diye sayılmadı. Canlı arkadaşlık/replay ve block kontrolleri korundu. İlk agent genişletmesinin cold-fixture kabul hataları geçerli ürün hatası sayılmadı; acceptance, aynı instance daveti gönderdikten sonraki ısınmış cache ile modellendi. Gerçek cold SDK kontrolü ayrı runtime raporundadır.

Düzeltme yalnız canonical dependency injection üzerinden send için mevcut `withSocialPairMetadata` kullanır. İkinci bir iç lock eklenmedi; deadlock yaratılmadı. Mevcut helper iki hesabın pre/post erasure kapılarını, pair cleanup’ını ve silinen target için404 çevirisini uygular. İlgili gerçek kaynak regresyonu **49/49 geçti**,0fail/skip. Üretim Auth/App Check ve RTDB kabulü değildir; fixture kapsamı `result.json` içindedir.

Güvenlik ajanının sonraki incelemesi otomatik sistemde “possible cybersecurity risk” içeriği olarak durdu. Root mevcut yerel testleri normal izinlerle doğruladı ve yalnız kanıtlanmış davet yolunu düzeltti. Flag verilen görev yeniden gönderilmedi; uzaktan işlem veya izin yükseltme yapılmadı. Sonuçlandırılmamış DM cache/friendship-shape adayları PASS veya yeni bug diye sayılmadı.

Commit `5831476`; hash’ler ve doğrudan TAP sonuçları bu dizindedir. Önceki native/görsel/Play engelleri açık; evrensel hatasızlık iddiası yoktur.
