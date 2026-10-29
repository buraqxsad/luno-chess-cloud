# LUNO Chess — canlı tutorial ve son bug avı

**RELEASE HOLD.** İstenen tutorial iyileştirmesi, iki doğrulanmış P1 ve bir P2 yönlendirme düzeltmesi tamamlandı. Açık native çökme ve zorunlu yayın kabulleri nedeniyle yayına hazır sonucu verilmedi.

Kaynak/build commit’i `dbdc0741caf7e27259d6a820d5273123e994198e`; dal `codex/cloud-transfer-20261027`. Son QA commit’i yalnız kanıt/devir notlarını ekler. V240 korunur; SDK, oyun kuralları,24 kart, hesap/ödül hakları ve imzalama kimliği değiştirilmedi. GitHub push yapılmadı.

Luno mevcut resmi korunarak Blender ile 16 kare hareketlendirildi: göz kırpma, konuşma hareketi, selam ve el hareketi. Uyuyan idle döngüsü ve yönerge tepkileri, reduced motion/lifecycle kontrolleriyle çalışır. İlk hamle ve kart adımları tek işlem başlıklarına ayrıldı. [Görsel/kapsam](ANIMATION.md) · [24 kart matrisi](cards/acceptance.md) · [önizleme](animation/luno-live-preview.webp).

**2 P1 ve 1 P2 kusuru** kapatıldı: oynanamayan kart/boş el yönlendirmeleri düzeltildi; gecikmiş Premium hesaplaması geçerli hakkı silebiliyordu; eski Play makbuzu yeni satın alma penceresinin kilidini açabiliyordu. Her biri önce failing regresyonla üretildi, sonra düzeltildi. [Kök nedenler/commit](BUGS.md) · [Değişen 17 dosya](CHANGED-FILES.md). Premium düzeltmesi ayrıca gerçek yerel RTDB SDK transaction’larıyla üç senaryoda sınandı; bağımsız SDK bağlantısı kalıcı veriyi doğruladı. [Yerel RTDB kanıtı](evidence/real-rtdb/REPORT.md). Play yanıtları simüleydi; üretim Firebase/Play kabulü değildir.

| Son kaynak doğrulaması | Sonuç |
| --- | --- |
| Tam Flutter, 433 dosya | **11747 pass / 97 fail / 0 skip** |
| Analyzer | Hata/uyarı yok |
| Yeni tutorial özellikleri / welcome güvenliği |22/22;8/8|
| Gerçek yerel RTDB Premium yarışı | Eski kodda3 hata tekrarlandı; düzeltilmiş kod3/3 geçti, Play yanıtları mock |
| Backend tam |1324 pass /0 fail /1 skip|
| TypeScript tam, Dart bridge etkin |376 pass /0 fail /0 skip|
| Dart/TS differential |3101 senaryo /10967 state ve legal set; sıfır ayrışma|

Koşular örtüşür; sayılar toplanmadı. Flutter başarısızlıklarının tamamı eski test adlarıyla ve gerçek pixel hata mesajlarıyla ayrı doğrulandı; [aday karşılaştırması](evidence/flutter/golden-comparison.json). [Sınırlı görsel inceleme](evidence/golden-review/README.md). Golden güncellenmedi; tam suite yeşil değildir. İlk tam Flutter denemesi availability hatası bulununca durduruldu; son sayılara eklenmedi. İlk fixture/ortam/inceleme başarısızlıkları [ham loglarda](logs) saklandı. [Test özeti](test-summary.json).

Güncel debug ARM64 ve profile x86_64 **test APK’ları** üretildi: aynı debug sertifikası/v2, com.luno.chess/1.6.3+19/min24/target36,750 asset ve statik ELF/ZIP16KB denetimi geçti. [Metadata/imza/hash](artifacts.json), [SHA-256](APK-SHA256SUMS). Mevcut upload anahtarı bulunmadığından release APK/AAB BLOCKED; yeni imza oluşturulmadı. +19’un Play geçmişindeki uygunluğu bilinmiyor.

Yeni APK native cihaza kurulmadı. V240’daki ilk gerçek API29 raster SIGSEGV çözülmüş sayılmaz. Tam native yolculuk, fiziksel performans/gerçek16KB, gerçek Google/Firebase/AppCheck/Integrity ve Play lisans/Console kabulü BLOCKED/NOT RUN. Yerel/mock kanıtlar bunların yerine sayılmadı. [Bütün kapılar ve somut nedenler](GATES.md).

Canlı deploy, gerçek ödeme, Play upload veya kamu yayını yapılmadı. **RELEASE HOLD korunur.**
