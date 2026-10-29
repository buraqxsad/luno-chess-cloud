# V240 — düzeltilen kusurlar

Üretim: **1 P2**. Test güvenilirliği: **2 P1 (QA)**. Yeni doğrulanıp düzeltilen üretim P0/P1 sayısı0; eski V238 düzeltmeleri yeniden sayılmadı.

| Kusur | Kök neden ve düzeltme | Commit | Kanıt |
| --- | --- | --- | --- |
| P2: açılışta sarı çift alt çizgiler | StartupGate altında Scaffold yok; ColoredBox, TextStyle.fallback dekorasyonunu miras alıyordu. LunoLoadingArtwork Material bağlamı sağlar. Mevcut resim/renk/kurallar korunur. |81f92d7|Native pre-fix ekran, başarısız regresyon,8 TR/EN/width/text testi ve12startup akışı PASS.|
| P1 QA: native-ses testi yük altında yanlış başarısız | Widget zamanı fake, ses bütçesi gerçek Stopwatch idi. Mevcut test-clock hook’u ve açık senaryo aralıkları; host-delay regresyonu. Üretim800/250ms stale budget değişmedi. |ac0dd98|Before-fix fail; final10/10; eski süre aşımı/cancellation assertion’ları korundu.|
| P1 QA: DM “too quick” testi gerçekte pencereyi aşıyor | Gerçek SDK read/replay gecikmesi1200ms’yi aşıyordu. Direct-handler fixture saati kayıtlı attemptAt+1’e bağlandı, finally ile geri alınır. Üretim throttle/record değişmedi. |831a7ae|Before200≠429; after429 ve tek mesaj; tam DM entegrasyonu PASS. HTTP Functions modu bu koşuda NOT RUN.|

Değişen üretim dosyası `luno_chess/lib/app.dart`; yeni `test/v240_startup_surface_test.dart`, güncellenen `test/v216_cosmetics_audio_test.dart`, `functions/test/dm.integration.js`. İlgisiz kaynak/golden/assertion silinmedi veya zayıflatılmadı.
