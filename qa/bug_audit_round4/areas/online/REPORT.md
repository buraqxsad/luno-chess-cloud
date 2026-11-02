# Final — legacy kayıt kurtarması da doğrulandı

Nonce ile yeni lease’lerde çakışma önlendi. Ardından nonce’sız, zaten çakışmış eski oda/davet rezervasyonlarının yeni backend’de hâlâ kilitlenebildiği mevcut-stored-state testleriyle ayrıca doğrulandı: nonce-only düzeltmede8pass/2fail. Aynı artık kapsam kusuru kapsamında `completeReservation` artık bir ortak gerçek canonical participant ile eski maçı yükler; token’sız rezervasyonun tam yakalanmış değerini CAS içinde karşılaştırarak yalnız aynı kaydı ve ona bağlı bozuk aktif/oda/davet pointer’larını temizler. Yaşayan canonical oyuncuların aktif eşleşmesi ve yeni token sahibi korunur. Friendly oyuncu istemeden ranked kuyruğa sokulmaz; eski ranked bekleyen peer gerekiyorsa kendi deck/joinedAt ile geri konur.

Exact d67cd index+friendly+rollout ile final13vaka **5pass/8fail**; son kaynakta13/13. İlgili dokuz dosya **62/62PASS**,0skip. Eski canonical maçın baytları, daha yeni rezervasyon sahibi ve gerçek aktif katılımcı mapping’leri kontrol edildi. Yeni kayıt önleme commit0662662, legacy kurtarma21a15c3. Bu, önceki deterministik-ID ailesinin kapsam eksiğidir; ayrı yeni aile sayılmadı. Aşağıdaki ilk aşama raporu tarihseldir; eski bozuk kayıtların kurtarılmadığı ilk sınır finaldeki iki tekrar üretim yolu için artık geçerli değildir.

# Oda/davet eşleşme kimliği — önceki ailede kapsam eksiği

**P1 düzeltildi; yeni bağımsız aile diye sayılmadı.** Önceki round3 queue düzeltmesinin oda ve davet admission yollarını kapsamadığı doğrulandı. Oda süresi geçtikten sonraki eski request-ID tekrarı veya daha sonra farklı arkadaşa aynı request-ID ile gönderilen davet yeni bir guest için eski canonical match’e çakışıyordu. Yeni guest’in get/cancel/enqueue yolları409 MATCH_CREATION_CONFLICT ile kilitleniyordu.

İlk4vaka2pass/2fail. Root’un exact d67cd index+friendly kaynaklarını salt okunur yükleyerek genişlettiği8vaka **5pass/3fail**; güncel kaynakta **8/8**, ilgili yedi dosyada **47/47PASS**,0skip. Ek kontroller yeni request akışı, pending idempotency, nonce’sız legacy oda/davet, zaten kaydedilmiş legacy matchId’nin önceliği ve aynı kod+createdAt ile değiştirilmiş lease’e ait eski snapshot’ın reddidir. İlk after denemesindeki boş `{}`/`null` memory-fixture farkı ayrı logda tutulur; gerçek RTDB boş alt düğümleri kaldırır. Aktif mapping bulunmaması koşulu korundu.

Her yeni private room/invite lease’ine sunucunun ürettiği nonce eklenir; deterministik matchID lease’e bağlanır. Pending tekrarlar mevcut lease/matchID’yi korur. Eski nonce’sız kayıtlar aynı eski ID türetmesini kullanır; kalıcı matchId varsa önceliklidir. Public payload veya istemci sözleşmesine alan eklenmedi. Kanıtlanan eski replay/collision yolları geçer; eski bozuk cloud kayıtlarının tamamının onarıldığı veya eski backend instance’larının yeni kodla aynı davrandığı iddia edilmez.

Online ajanının sonraki yanıtı otomatik içerik incelemesinde “possible cybersecurity risk” nedeniyle durdu. Root mevcut normal yerel oyun API testini, olumlu uyumluluk kontrollerini ve minimal düzeltmeyi tamamladı. Flag edilen görev yeniden gönderilmedi; uzaktan servis, gerçek kullanıcı hesabı veya izin yükseltme kullanılmadı. Bu sonuç gerçek Firebase veya Android kabulü değildir.

Commit0662662. Kaynak/test hash’leri result.json; bütün başarısız ve geçen ham TAP dosyaları bu dizindedir.
