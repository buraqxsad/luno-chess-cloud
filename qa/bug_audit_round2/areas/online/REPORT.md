# İkinci online avı — 1 P2 düzeltildi

Geçerli Auth/AppCheck handler üzerinden enqueueBattleV1/createBattleV1Room, entry/migration sonrası hesap silme kazanırsa eski private deck/host kaydını yeniden yazabiliyordu. Dispatcher403 döndürse de queue/room metadata kalıyordu.

Önce6vaka:4pass/2fail. Root patch uyguladı: canonical iki admission route mevcut writeAccountMetadata pre/post deletion kapıları ve battleV1.leaveAccount cleanup'ı ile sarılır. Sistem cleanup akışı wrapper'a alınmaz; recursive gate eklenmez. Son mevcut6test root'un standart yürütme izinleriyle doğrudan Node üzerinden6/6PASS; source adapter/library dosyaları değiştirilmedi.

Ajanın ek4kontrol yazma+Node çalıştırma birleşik çağrısı otomatik onay incelemesinde kullanım sınırında reddedildi ve hiç çalışmadı. Bu ek4kontrol PASS sayılmadı; kontrol aşılmadı. Root daha dar, mevcut test dosyasını kaynak mutasyonu olmadan normal izinlerle doğruladı. İlk yanlış afterTransaction snapshot fixture denemesi invalid logda korunur; gerçek bug sayısına katılmaz.

Kanıt: admission-erasure-before.log, admission-erasure-after-root.log ve exit dosyası. Önceki cursor/TTL fix'leri yeniden sayılmadı. Peer/reservation geniş adayları bu tur yeni doğrulanmış bug diye ilan edilmedi. Gerçek Firebase/Android/Play kabulü değildir. Canlı deploy/ödeme/upload yok.
