# LUNO Chess - Bulut Codex Devir Notu

Son dogrulama/aktarim tarihi: 27 Ekim 2026. Bu dosya kaynak aktarimini anlatir;
oyunun kusursuz, canli servislerin tamamen kabul edilmis veya Play yayininin
onaylanmis oldugu anlamina gelmez.

## 2 Kasım — ikinci sistem taraması

**Bu turda doğrulanıp açık bırakılan yeni kaynak hatası: 0. Genel karar:
RELEASE HOLD.** [Son rapor](qa/bug_audit_round2/REPORT.md),
[kusur ve commit matrisi](qa/bug_audit_round2/BUGS.md),
[kapsam sonucu](qa/bug_audit_round2/scope-clean-status.json) ve
[açık sorunlar](qa/bug_audit_round2/OPEN-ISSUES.md). Bu, bütün oyunun hatasız olduğunun kanıtı değildir.
Build ve tam regresyon kaynağı `9d41c5055006907ee2dafdf8e5daf70bb9f2c7a3`; son QA commit’i çalışma kodunu değiştirmez.

- 6 yeni hata bulundu ve kapatıldı: 1 P1, 5 P2. Güncel inactive owned subscription;
  billing snapshot sırası; üstü kapalı Friendly route; silme sonrası V1 admission;
  DM raporlamada konuşma üyeliği; eski push bildirimlerinin silinmesi.
  Önceki yedi düzeltme ve aynı düzeltmenin alt senaryoları yeniden sayılmadı.
- Tam backend: 1399 geçti / 0 başarısız / 1 atlandı.
  TypeScript: 376 / 0 / 0. Differential:
  3101 senaryo, 10967 durum ve tam geçerli hamle kümesi; 0 ayrışma.
  Analiz temiz. Tam Flutter: 11776 geçti /
  97 başarısız / 0 atlandı,
  437 dosya. 97 tarihsel görsel fark açık; golden referansları korundu.
- Son gerçek yerel RTDB/Admin SDK koşusu 4/4 geçti. Bağımsız SDK bağlantısı kalıcı
  veriyi doğruladı. Önceki timeout’un test düzeneği nedeni: Admin dış faye yerine
  bundled standalone transport kullanıyor. Yalnız kesin loopback için bir proxy
  seçimi koşulu bellekte değişti; SDK disk dosyası, ortam ve header’lar korundu.
  Google Play yanıtları fake; üretim kabulü değildir.
- Güncel ARM64 debug test APK’sı üretildi: aynı imza, com.luno.chess/1.6.3+19,
  minSdk 24 / targetSdk 36, 750 asset ve ELF/ZIP statik 16 KB kontrolleri geçti.
  Mevcut upload key yok; release APK/AAB BLOCKED. +19 Play geçmişi doğrulanmadı.
- Eski API 29 raster SIGSEGV açık. Yeni APK ile native oyuncu yolculuğu, fiziksel
  FPS/RAM/p95–p99 ve gerçek 16 KB runtime NOT RUN. Gerçek Firebase/Google/App Check/
  Integrity, Play lisans/Console/Pre-launch kabulleri BLOCKED. [Kapılar](qa/bug_audit_round2/GATES.md).
- Canlı deploy, gerçek ödeme, Play upload/yayın veya GitHub push yapılmadı.
  Kanıt/APK/source bundle/QA ZIP/hash: `/workspace/luno-review/bug-audit-round2/`.

Aşağıdaki kayıtlar tarihseldir; yeni dört SDK başarısı geçmiş timeout kayıtlarını silmez.

## 1 Kasım teslimi — sistem çapında bug avı

**RELEASE HOLD.** En yeni [rapor](qa/system_bug_hunt/REPORT.md),
[kök nedenler](qa/system_bug_hunt/BUGS.md), [24 kart matrisi](qa/system_bug_hunt/cards/acceptance.md)
ve [açık P1/kabul engelleri](qa/system_bug_hunt/OPEN-ISSUES.md).
Son tam Flutter/build kaynağı `219b1daf5f2329c558bc1ac7a3cf6c781e316514`; son QA commit’i
runtime değiştirmez. V240, canlı Luno, kurallar/assetler ve imza kimliği korunur.

- 7 yeni hata ailesi kapatıldı:3P1,4P2. Refund sonrası geç currency grant;
  subscription eski provider/claim/sonuç yarışları; pending settlement starvation;
  expired queue sonrası room join; silme sonrası presence; geç refreshState
  completion; stale modal ilk karesi. Önceki düzeltmeler yeniden sayılmadı.
- Ekonomi: refund10+subscription20 yeni vaka; ilgili208/208. Profil/token claim
  fencing, fresh ilk registration doğrulaması ve final completion CAS. Geçerli
  yenileme/legacy claim ve tombstone korunur; backend canlıya deploy edilmedi.
- Tam Flutter:11759 pass /97 fail /
  0 skip, 435 dosya. Tarihsel görsel karşılaştırmalar
  FAIL kalır; golden güncellenmedi. Analiz temiz. Tam backend:1365/0/1;
  TypeScript:376/0/0; differential3101senaryo/10967state,
  sıfır ayrışma. Node doğrudan herdosyada gerçek TAP case sayılarıyla çalıştı.
- Gerçek yerel presence RTDB rules12/12. Ek yeni Billing gerçek SDK proof’u iki
  bounded timeout nedeniyle FAIL/NOTCOMPLETE;0durableobservation. Mock ve geçmiş
  yerel başarılar bu eksik kapıyı kapatmaz. Kanıtların ilk başarısız koşuları korunur.
- Yeni ARM64 debug test APK’sı üretildi; com.luno.chess/1.6.3+19/min24/target36,
  aynı debug sertifikası,750asset ve statik ELF/ZIP16KB PASS. Upload anahtarı yok;
  release APK/AAB BLOCKED. +19 Play geçmişiyle doğrulanmadı.
- Yeni APK native cihazda çalıştırılmadı. V240 raster SIGSEGV, native oyuncu
  yolculuğu, fiziksel performans/gerçek16KB, gerçek Firebase/Google/AppCheck/
  Integrity ve Play lisans/Console kabulleri açık. Canlı deploy, para, Play
  upload/yayın veya GitHub push yapılmadı.

Tam dış kanıt/APK/source bundle/QA ZIP/SHA-256:
`/workspace/luno-review/system-bug-hunt/`. Aşağıdaki kayıtlar tarihseldir.

## 29 Ekim — V240 sonrası canlı tutorial ve bug avı

**RELEASE HOLD.** En yeni teslim [qa/tutorial_live/REPORT.md](qa/tutorial_live/REPORT.md),
[animasyon önizlemesi](qa/tutorial_live/animation/luno-live-preview.webp) ve
[yayın kapıları](qa/tutorial_live/GATES.md) içindedir. Build ve son tam Flutter
regresyonunun kesin kaynağı `dbdc0741caf7e27259d6a820d5273123e994198e`;
son QA/devir commit’i çalışma kodunu değiştirmez. Dal ve V240 düzeltmeleri korunur.

- Kullanıcının canlı Luno isteği uygulandı: orijinal çizim Blender ile 16 kare
  hareketlendirildi; göz kırpma, küçük ağız hareketi, baş selamı ve el dalgası.
  Tek lossless atlas 324110 bayt; mantıksal decode 1.5625 MiB, cihaz RAM ölçümü
  değildir. Uyuyan idle timer; reduced motion, background ve route temizliği.
  İlk hamle/kart yönergeleri tek işleme ayrılır; ilerleme ve oyun kuralları aynı.
- 2 P1 düzeltildi: gecikmiş claim snapshot’ının Premium hakkını silmesi veya
  iptal edilmiş hakkı geri açması; eski Play makbuzunun yeni satın alma kilidini
  çözmesi. 1 P2: oynanamayan kart ve boş elde imkânsız hedef/kart seçme yönergesi.
  Önce failing regresyon, sonra düzeltme. Backend gerçek yerel Admin SDK/RTDB
  ile ayrıca eski kaynakta 3 fail, düzeltmede 3 pass; Play yanıtları mock.
- Son tam Flutter: 11747 pass / 97 fail / 0 skip, 433 dosya. 97 görsel FAIL,
  eski V239/V240 adaylarıyla aynı; golden değişmedi, suite PASS sayılmaz.
  Analiz temiz; backend 1324/0/1, TS 376/0/0; differential 3101 senaryo,
  10967 state/legal set, sıfır ayrışma. Tutorial dar kapsam 42/42; örtüşen
  test sayıları toplanmaz. Eski kaynakla durdurulan koşu ayrı arşivlendi.
- İki yeni test APK’sı üretildi: debug ARM64 / profile x86_64, aynı debug
  sertifikası; 1.6.3+19, min24/target36, 750 asset ve statik ELF/ZIP 16KB PASS.
  Runtime payload’ları V240’tan farklı, güncel commit’ten üretildi. Mevcut upload
  imzası yok; release APK/AAB BLOCKED, yeni imza oluşturulmadı.
- Yeni APK native cihaza kurulmadı. V240’taki ilk raster SIGSEGV açık; tam
  native yolculuk, fiziksel FPS/p95–p99/RAM, gerçek 16KB runtime NOT RUN.
  Üretim Firebase/AppCheck/Google/Play Integrity, lisanslı ödeme ve Console
  kabulü BLOCKED. Canlı deploy, para, Play upload/yayın veya GitHub push yok.

APK, kaynak bundle’ı, QA arşivi ve SHA-256 listesi ayrıca
`/workspace/luno-review/tutorial-live/` içindedir. V240 ve aşağıdaki eski kayıtlar
tarihsel sonuçlardır; güncel teslimin yerine okunmamalı.

## 29 Ekim bulut geliştirmesi — V240 / final Android kalite çalışması

**RELEASE HOLD.** Güncel teslim kanıtı [qa/v240/REPORT.md](qa/v240/REPORT.md),
[24 kart matrisi](qa/v240/cards/acceptance.md), [kabul kapıları](qa/v240/GATES.md).
V239 çalışma ağacı `1247012a429f4a329440dec5983b4fb09e07f1b4` ile korunarak
commitlendi. Güncel build kaynağı `831a7ae11f28094c4b54f37415c80031ba1fd029`;
son QA/devir commit’i runtime değiştirmez. Dal aynı, GitHub push yapılmadı.

- 1 üretim P2 düzeltildi: Scaffold öncesi loading artwork’ünün sarı fallback
  metin alt çizgileri Material bağlamıyla giderildi. 8 TR/EN/dar-geniş/büyük yazı
  regresyonu; önce fail, sonra PASS. İki QA zamanlama kusuru da düzeltildi;
  üretim ses süresi ve DM throttle/assertion’ları korunur. Yeni özellik yok.
- Tam Flutter 11711 pass / 97 fail / 0 skip, 430 dosya; 97 tarihsel görsel fark
  eski V239 adaylarıyla byte-identical, golden güncellenmedi. Analiz temiz;
  son TR 77/77, EN 76/76. Backend 1312/0/1; TS 376/0/0; differential
  3101 senaryo / 10967 state ve legal set / sıfır ayrışma. Yerel Auth/RTDB
  12 ayrı suite son durumda geçti; ilk DM fixture hatası ve takibi saklandı.
- Güncel debug ARM64 ve profile x86_64 test APK’ları üretildi. Sürüm
  1.6.3+19, min24/target36; eski debug sertifikası, SHA, 749 asset ve static
  ELF/ZIP 16KB denetimi geçti. Upload imzası yok; release APK/AAB BLOCKED.
  +19’un Play geçmişindeki uygunluğu bilinmiyor; key/kimlik değiştirilmedi.
- API29 gerçek emülatörün ilk güncel profile açılışında raster SIGSEGV kaydedildi.
  V239/V240 90 saniyelik default tekrarları welcome 1/3 ekranına ulaştı; ilk
  crash’in kök nedenini veya çözüldüğünü kanıtlamaz. Software tanı da ekranı
  çizdi, fakat tutorial etkileşimi ilerlemedi; tam native kabul geçilmedi.
  Fiziksel cihaz, uzun maç FPS/build-raster p95–p99/GPU RAM ve gerçek16KB
  runtime NOT RUN. VM `adb emu kill` ile kapatıldı; eski paused-VM varsayımını
  kullanma. API35 açılmadı; guest dış ağı kapalıydı, yeni snapshot yok.
- Gerçek Firebase/AppCheck/Play Integrity, Google, Play lisans ödemesi ve Console
  beyanları/track/pre-launch/koşullu kapalı test kabulü tamamlanmadı. Canlı deploy,
  gerçek para, Play upload ve kamu yayını yapılmadı.

Tam günlükler ve iki APK ayrıca `/workspace/luno-review/v240/` içindedir.
Aşağıdaki V239 ve eski kayıtlar tarihsel sonuçlardır; V240 kabulü diye okunmamalı.

## 28 Ekim bulut geliştirmesi — V239 / ilk yayın kabul adayı

Dal ve HEAD korundu: `codex/cloud-transfer-20261027`,
`14780e10e9b511aababd009517507425890c4840`. V237/V238 runtime düzeltmeleri ve
animasyonlar korundu; yeni oyun özelliği yok. Yerel sürüm adayı `1.6.3+19`;
Play Console geçmişinde 19'un kullanılabilirliği doğrulanmadı.

- Yeni üretim oyun/backend bug düzeltmesi 0; release verifier'da iki somut
  sorun giderildi: eski build17/sabit sürüm varsayımı ve alternatif Gradle
  signing-properties yolunun yok sayılması. Java21/PATH kontrolü eklendi.
- Yeni 5 backend yarış/sınır ve 77 Flutter kabul testi eklendi. Son TR kart/ses
  77/77, EN kart 76/76; analiz temiz. Tam Flutter **11701 pass / 99 fail /
  0 skip**: 97 tarihsel golden farkı; diğer iki ilk-koşu hatası hedefli takipte
  geçti. Tam suite yeşil sayılmaz; golden'lar değiştirilmedi.
- Backend 1312 pass / 0 fail / 1 opt-in skip; TypeScript 376/376 (Dart bridge
  etkin). Differential 3101 senaryo / 10967 state ve legal set / sıfır ayrışma.
  Yerel Auth/RTDB 21 ayrı suite; ilk iki timeout değişmemiş testlerle tekrarda
  geçti. İki ayrı backend süreci günlük ödülde tek grant/replay değişmezliğini
  doğruladı. Bunlar üretim Play/iki fiziksel cihaz kabulü değildir.
- Debug APK ve yalnız x86_64 için profile APK üretildi; aynı debug sertifikası,
  1.6.3+19/min24/target36, 749 asset hash'i, ELF/16KB ZIP hizalaması doğrulandı.
  Release AAB ve APK gerçek build denemeleri eksik upload imzasında guard ile
  durdu; koruma atlanmadı. İmzalı final AAB yok.
- Aynı API29 AVD snapshot yüklenemeyince açıldı; yeni profile APK kuruldu ve
  Luno welcome gerçek Android framebuffer'ında çizildi. SystemUI ANR görüldü;
  tam oyuncu kabulü geçilmedi. Başlangıç PSS tek örnek 129855KiB; battle/tepe
  RAM değildir. Guest IPv4/IPv6 dış ağı engellendi; VM sonunda `avd stop` ile
  duraklatıldı, yeni snapshot kaydedilmedi. Ölçülen kernel sayfa boyutu4096B.
- 24 kartın TR/EN gerçek Flutter savaş ekranı matrisi, 106 güncel widget PNG,
  Blender48 kare denetimi ve host atlas cache/decode ölçümü kaydedildi. 9MiB
  host cache cihaz RAM/GPU ölçümü değildir. Android FPS/build-raster p95–p99,
  gerçek16KB/Play Integrity/lisans testi ve tek gerçek oyuncu zinciri geçilmedi.

Güncel kanıtlar: `/workspace/luno-review/v239/REPORT.md`, `verification.json`,
`animations/card-acceptance.md`, `PLAY-GATES.md`, `performance.json`.
APK/hash'ler ve değişen kaynakların yedeği aynı dizindedir. Kaynaklar çalışma
ağacında; commit/push, canlı deploy, gerçek ödeme ve Play yayın yapılmadı.
**RELEASE HOLD** devam eder. Android snapshot/başlatma denemelerinin güncel
sonucu için `v239/android/device/` kaydına bakın; eski paused-VM varsayımını
doğrulamadan kullanmayın.

## 28 Ekim bulut geliştirmesi — V238 / ilk yayın hazırlığı

Kullanıcı ilk kamuya açık yayını hazırladığımızı doğruladı. V237 korunarak:

- 24 karta farklı sonlu vektör hareketi; Blender/Cycles ile kristal, zincir ve
  sis atlasları eklendi. Üç yeni dosya toplam 421148 bayt. Dört ortak atlasın
  ham RGBA toplamı 9 MiB; bu gerçek cihaz RAM/FPS ölçümü değildir. Orijinal
  sanat, kurallar, mana, hedef gizliliği ve süreler korunur. Kaynaklar
  `luno_chess/artwork/v238/` altında yeniden üretilebilir.
- Hesap silme sonrası gecikmiş V1 migration'ın yan hesap kaydı oluşturması,
  gece yarısında ters sıralı günlük ödülün ilerlemeyi geri alması, geç emoji
  yanıtının yeni pencereyi kapatması ve ilk çizim öncesi hesap değişiminde
  eski özel pencerenin görünmesi düzeltildi; negatif regresyonlar eklendi.
- Son seçilmiş Flutter regresyonu 447/447; backend
  1307 pass / 0 fail / 1 skip; TS kuralları
  373 pass / 0 fail / 3 skip. Tam analiz temiz.
  Bu sonuç tam Flutter suite'inin yeşil olduğu anlamına gelmez; V237'deki 97
  tarihsel görsel fark çözülmüş sayılmaz, golden'lar değiştirilmedi.
- Yerel yayın preflight'ı 17/17; gerçek aktif Gradle
  `preReleaseBuild`, eksik/yarım imza bilgisi ve olmayan keystore ile üç
  durumda doğru imza guard'ında durdu. Debug APK kimlik değiştirmeden üretildi.

Yeni test APK'sı: `/workspace/luno-review/v238/Luno-Chess-v238-debug.apk`, 241367917 bayt.
SHA-256: `288fc337494d2a83ad6146abd1b2a3876dcd117d3468013a8b3530504601cf2b`. v2 imza, önceki debug sertifikası, ARM64/x86_64 ve
dört atlasın paketteki birebir içeriği doğrulandı. Sürüm `1.6.3+18` korundu.
İlk kamu yayını için önceki test-track kodları ayrıca kontrol edilmelidir.

Güncel rapor/kanıt: `/workspace/luno-review/v238/REPORT.md`, `verification.json`.
Altı gerçek Flutter animasyon önizlemesi `vfx/previews/` içindedir. Yeni QA
çıktıları inceleme dizinine taşındı; tracked fixture'lar korunur. Değişen
kaynakların V237+V238 yedeği `source-changes.zip` içindedir. Çalışma ağacı henüz
commit/push edilmedi. SDK/bağımlılık, release kimliği ve tarihsel manifest korunur.

**RELEASE HOLD:** imzalı final AAB/Play test-track teslimi, sağlıklı gerçek
Android/16 KB runtime/FPS, Google/App Check, iki hesap online ve Play ödeme/
restore/refund/RTDN kabulü ile ilk mağaza beyanları tamamlanmadı. API29 VM
duraklatılmış kalır. Production deploy, Play upload veya yayın yapılmadı.

## 28 Ekim bulut gelistirmesi — V237

Asagidaki eski aktarim notlari tarihsel kayittir. 28 Ekim calismasinda yarim
App Check izin-listesi handler'a baglandi; Flutter oturum sahipligi hatalari,
aktarim girdileri ve rehber/efektler uzerinde yeni degisiklikler yapildi.
Guncel kanitlar bulutta `/workspace/luno-upgrade/` altindadir; ilk temiz aktarim
incelemesi `/workspace/luno-review/INCELEME.md` tarihsel olarak korunur.

- Ana menu/Ayarlar Rehber'i canli TR/EN ogrenme merkezini acar. Orijinal Luno
  portresi, sonlu tepkiler, secilebilir on ders, kucuk tahta ornegi, uygulamali
  tekrar, Akademi ve kart katalog baglantilari vardir. Onboarding ve mevcut
  ilerleme/oduller korunur; hareket azaltma ve yasam dongusu dikkate alinir.
- Blender'da ozgun halka uretildi; ImageMagick bloom ve kayipsiz WebP atlasla
  16 kare tek 164.026 baytlik dokuya alindi. Uretim kaynaklari
  `luno_chess/artwork/v237/`, runtime `lib/widgets/luno_arcane_halo.dart`.
  Kartlara ozel vektorler korunarak ucus izleri/parcaciklar iyilestirildi.
  Oyun kurali, hedef gizliligi, mana ve gorsel sureler degistirilmedi.
- Hazirlik/hesap kurtarma beklenirken eski isteklerin yeni hesabi sahiplenmesi
  ve dispose sonrasi veritabani okumalari engellendi; regresyonlar eklendi.
- Eksik eski HTML hero girdisi, native orijinalinden byte-identical kopyayla
  geri kondu. Kayip QA oracle'inin orijinali bulunamadi: mevcut elle yazilmis
  geometri konumlari ve acik sozlesmeye dayali **yeni** 72 bagimsiz kontrol
  yazildi. Kayip dosyanin geri getirildigi veya bilinmeyen orijinal kapsamla
  esdeger oldugu iddia edilmez. Provenans ve sinirlar:
  `luno_chess/test/helpers/V223_PROPHECY_CHECKS.md`.
- `TRANSFER_MANIFEST.json`, ilk aktarimin tarihsel hash listesidir. V237 kaynak
  degisikliklerini tanimlamaz ve yeni kodu ona uydurmak icin yeniden yazilmadi.

28 Ekim son kanit: tam Flutter analizi temiz; backend 1301 pass / 0 fail / 1
kontrollu skip. Ilk genis Flutter kesfi 11412 pass / 278 fail verdi; bu final
yesil suite degildir. Ardindan 22 islevsel basarisiz dosya kendi hedefli
tekrarlarinda dogrulandi. Son rehber/kayit grubu 15/15, responsive grup 145/145
gecti; ayrintili ortusmeyen kanit eslemesi bulut raporundadir. 97 tarihsel
gorsel karsilastirma farki saklandi; golden'lar ezilmedi. 50 battle golden
adayinin eski temiz commit'te de V237 ile byte-identical oldugu kanitlandi.

Yeni debug APK: `/workspace/luno-upgrade/Luno-Chess-v237-debug.apk`,
240934629 bayt, ARM64 + x86_64; v2 imzasi ve onceki bulut debug sertifikasiyla
eslesmesi dogrulandi. Yeni halo dokusunun APK icindeki kopyasi kaynakla birebir.
Uygulama surumu 1.6.3+18 korundu; bu bir Play/release paketi degildir. Bu yeni
APK cihazda kurulum/oynanabilirlik kabulunden gecmis sayilmaz. Guncel rapor ve
sonuclar: `/workspace/luno-upgrade/REPORT.md`, `verification.json`.
Kaynak degisiklikleri calisma agacinda; henuz commit/push yapilmadi. Yalniz
degisen kaynaklarin yedegi `source-changes.zip` icindedir.

Bu calisma SDK/paket yukseltmesi, production deploy veya release imzalama
degisikligi icermez. Canli Google/App Check/Play billing ve donanim FPS kabul
kapilari ayridir; onceki **RELEASE HOLD** karari yalniz yerel testlerle kalkmaz.

Bulutta her komuttan once:

```bash
source /workspace/toolchains/luno-env.sh
cd /workspace/luno-chess/luno_chess
```

Bu script Flutter 3.47.1 / Dart 3.13.1 / Java 21.0.12 / Node 22.23.3 secimini
yapar; daha yeni baseline Flutter ile projeyi yukseltme. API 29 VM duraklatildi;
KVM/GPU olmadigi icin System UI ANR'leri goruldu. Widget render/testleri yerel
UI gelistirme kanitidir; emulator boot veya APK derlemek cihaz kabulunu kanitlamaz.

## Dogru Proje

- **Aktif uygulama:** `luno_chess/`, yerel Flutter/Dart; giris `lib/main.dart`.
- **Sunucu:** `functions/`, Firebase Functions Node.js; Battle V1 TypeScript
  motoru `functions/rules-v1/`.
- **Ortak sozlesme/fixture:** `battle_contract/v1/`.
- `luno_android/` ve kok HTML/JS dosyalarinin aktarilan kucuk alt kumesi,
  mevcut backend kaynak-sozlesme testlerinin uyumluluk girdileridir. Yeni
  uygulama olarak gelistirilmeyecek veya Android ciktisi buradan alinmayacak.
- Kaynak surumu `1.6.3+18`; oyun protokolu ayri: `LUNO_BATTLE_V1`.
- Yerel eski Git HEAD: `9e0ab47f913a5a20146a4c64e5858b5dd77bf304`, fakat yuzlerce
  modified/untracked dosya vardi. Bu nedenle eski HEAD son uygulamayi tanimlamaz.
  Temiz aktarim commit'i gercek mevcut dosya kopyasini tanimlar.

Orijinal yerel proje, eski Git gecmisi, yedekler ve imzalama malzemesi yerinde
korundu. Yeni ozel depo temiz bir aktarim kopyasidir; eski public `luno-chess`
deposunun gecmisi/remote'u yeniden yazilmadi. SDK, derleme, onbellek, APK/AAB,
node_modules, ZIP yedekleri ve eski ekran-ciktisi yiginlari tasinmadi. Secilen
test fixture/golden dosyalari, klasor adlari eski olsa da kaynak girdisi olarak
korundu. `TRANSFER_MANIFEST.json` aktarilan kaynaklarin goreli hash listesidir.

## Dogrulanan Arac Zinciri

Mevcut yerel Flutter SDK metadata'sindan okunan degerler; aktarim icin upgrade
yapilmadi:

| Bilesen | Mevcut deger |
| --- | --- |
| Flutter | 3.47.1, stable; framework `6655482ec06e547f90abf8ae7590466f4415978d` |
| Dart | 3.13.1; pubspec alt siniri `^3.7.0` aynen korundu |
| FVM | Mevcut projede `.fvmrc`/FVM ayari bulunmadi; yeni pin eklenmedi |
| Java | Yerelde Microsoft OpenJDK 21.0.12.8 kullanildi; Java/Kotlin hedefi 17 |
| Gradle wrapper | 9.1.0-all, depodaki wrapper ile |
| Android Gradle Plugin | 9.0.1 |
| Kotlin plugin | 2.3.20; `android.builtInKotlin=false`, `android.newDsl=false` |
| Google Services plugin | 4.4.3 |
| Android | compileSdk 36, targetSdk 36, minSdk 24; Flutter extension varsayilanlari |
| NDK | 28.2.13676358; mevcut Flutter extension varsayilani |
| Node.js | 22; yerelde 22.23.3 |
| TypeScript | 5.9.3, `functions/rules-v1/package-lock.json` ile kilitli |

Bulut ortaminin bunlari hazir sundugu dogrulanmadi. Ayni surumleri kur;
`flutter upgrade`, `pub upgrade`, `npm update` veya mimari/oyun kurali
degisikligi bu aktarimin parcasi degildir. Gradle dagitimi ve pub/npm paketleri
ilk kurulumda agdan indirilir; yerel SDK/onbellekler Git'te yoktur.

## Kurulum ve Komutlar

Depo kokunden, Flutter ve Android SDK PATH/ortam ayarlari yapildiktan sonra:

```sh
cd luno_chess
flutter --version
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build apk --debug
```

`android/local.properties` makineye ozeldir ve Git'te yoktur. `flutter pub get`
ve Flutter Android komutlari kullanilan SDK yolunu olusturur; gerekirse
`flutter.sdk` ve `sdk.dir` degerlerini yalniz kendi makinen icin ayarla.
Android SDK lisanslarini kendi ortaminda kabul et. Gradle wrapper scriptleri
ve wrapper JAR'i gereklidir ve aktarima dahildir. Linux'ta wrapper scripti
calistirilabilir bitiyle commit edilir.

Hizli, odakli kaynak regresyonu:

```sh
flutter test --concurrency=1 test/v236_google_credentials_test.dart test/v236_google_restore_test.dart test/v236_deck_metrics_test.dart test/v236_hotseat_privacy_test.dart
flutter test --concurrency=1 test/v230_learning_ui_test.dart test/v235_learning_acceptance_test.dart test/v236_tutorial_layout_test.dart test/online_deleted_session_recovery_test.dart
```

Tam `flutter analyze`/tum test klasorunun bulutta yesil oldugu iddia edilmez.
Asagidaki kanitlar secilmis dosyalara aittir; eski gorsel snapshot testleri
guncel UI ile fark gosterebilir. Beklentileri korlemesine gevsetme veya
`--update-goldens` ile hatayi gizleme; once eski/yeni goruntuyu incele.

Backend:

```sh
cd functions
npm ci
npm --prefix rules-v1 ci
npm run build:battle
node --check index.js
node --test --test-concurrency=1 'test/*.test.js'
node --test --test-concurrency=1 'rules-v1/dist/test/*.test.js'
```

`rules-v1/dist/` TypeScript ciktisidir, Git'te yoktur; once build gerekir.
`node_modules` ve Pub onbellegini kendin olustur. Yerel path/git Pub bagimliligi,
NPM file/link bagimliligi veya Git submodule bulunursa aktarim denetimi bunu
ayrica raporlar; sessizce disarida birakilmaz.

Projede uygulama flavor'i bulunmadi. Normal debug icin `--flavor` veya gizli
bir `--dart-define` gerekmiyor. Capture testleri `CAPTURE_SCREEN`,
`CAPTURE_SCROLL`, `V214_CAPTURE`, `V216_PHASE`, `LUNO_QA_CAPTURE_DIRECTORY`
gibi test-ozel define'lar kullanir. Bunlari uretim modlari/sirlar sanma.

## Dis Servisler ve Sirlar

- Firebase projesi: `luno-chess`; paket: `com.luno.chess`.
- API: `https://europe-west1-luno-chess.cloudfunctions.net/lunoApi`.
- RTDB: `https://luno-chess-default-rtdb.firebaseio.com`.
- Android `google-services.json` gerekli **istemci yapilandirmasidir**;
  servis-hesabi ozel anahtari degildir ve aktarima dahildir.
- Yerel `.env.example` yalniz degisken adlarini icerir. Native istemci `.env`
  okuyup otomatik sunucu degistirmez.
- Sunucu/admin ihtiyaclari: `GOOGLE_APPLICATION_CREDENTIALS`, `GCLOUD_PROJECT`,
  `FIREBASE_DATABASE_URL`, `LUNO_BILLING_RTDN_TOPIC`. Gercek servis-hesabi JSON'u,
  CLI refresh/access tokenlari ve hesap sifreleri Git'e konmaz. Uretimde
  normal Firebase/Google Cloud servis kimligi kullanilir.
- Emulator: `FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_DATABASE_EMULATOR_HOST`,
  `LUNO_DB_EMULATOR_NAMESPACE`; gercek servise baglanirken bunlari set etme.
- Release imzalama yerelde sakli `key.properties`/keystore gerektirir; adlar:
  `storeFile`, `storePassword`, `keyAlias`, `keyPassword`; alternatif Gradle
  ozelligi `lunoSigningPropertiesFile`. Mevcut imzalama kimligini degistirme.
  Buluta key veya sifre yuklenmedi. Debug derlemesi bunlari istememelidir.
- Google Sign-In icin dogru package/SHA OAuth kaydi; release icin Play
  Integrity + Firebase App Check; odemeler icin Google Play urunleri, Publisher
  yetkisi, lisans test hesabi ve RTDN ayari ayri servis kabul kapilaridir.
- Bulut Codex'in bu servislerde oturumu/yetkisi otomatik tasinmaz. Gerekirse
  resmi GitHub/Firebase hesap baglama akislarini kullan; sir degerlerini
  sohbet, DEVAM.md veya loglara yapistirma.

`firebase.json` ozellikle `database.rules.production.json` dosyasini secer.
Koktaki eski `database.rules.json` dosyasini uretime dagitma. Hosting ayari eski
uyumluluk kaynaklarina isaret eder; bu aktarim bir Hosting yayini degildir.
Acikca istenmedikce `firebase deploy` calistirma. Onayli sunucu dagitiminda
`--only functions,database --project luno-chess` kapsamini kullan; Hosting'i,
oyuncu-sifirlama scriptlerini veya veri temizligini kendiliginden calistirma.

## Son Yapilanlar ve Gercek Kanit

V236'da hesap geri yukleme/native Google credential akis, hotseat gizlilik
perdesi ve lifecycle, kayip deste-save yaniti uzlastirma, kaydedilmemis deste
cikis korumasi, deste metrikleri, kucuk ekran tahta/egitim yerlesimi, kullanici
adi buyuk-yazi alani, font lisans bildirimi, kismi ekonomi islem-kaniti
korumasi ve bildirim temizleme indeksi uzerinde calisildi.

22-23 Ekim tarihli tutulmus loglar:

| Kanit | Sonuc / sinir |
| --- | --- |
| Ilk Flutter taramasi, 117 dosya | 4989 pass / 51 fail; tek basina yesil degil |
| Son etkilenen Flutter turu | 250 pass / 0 fail; 51 hatanin kategorileri yeniden kontrol edildi |
| Egitim uzlastirma | 89 pass / 0 fail; onceki turle ortusur |
| Menu renderlari | 62 pass / 0 fail; gercek Flutter test renderi, fiziksel cihaz degil |
| Backend eski tam turu | 1267 pass / 0 fail / 1 skip; asagidaki yeni yarim patch'ten ONCE |
| TS kurallari | 373 pass / 0 fail / 3 skip |
| Dart/TS differential | 3101 senaryo, 10967 durum/legal-set karsilastirmasi, raporda fark yok |
| Son secilmis analiz | 119 girdi; no issues; tum olasi dosyalar/cihazlar icin garanti degil |

Bu sayilar ortustugu icin toplanarak yeni bir basari yuzdesi uretilmez.
Kanitarin secilmis metinleri `luno_chess/qa/v236/` ve
`luno_chess/qa/v235-v226/` altindadir. Tam ekran PNG yiginlari/yerel derleme
ciktilari yuklenmedi. Eski kaynak/binary imzalama/cihaz kanitlari bugunku
kaynak icin yeni basari sonucu gibi kullanilamaz.

## ONEMLI: Aktarim Aninda Yarim Kalan Is

26 Ekim online kabul calismasi aktarim talebiyle durduruldu:

1. `functions/lib/app-check-policy.js` ve
   `functions/test/v236-app-check-policy.test.js` eklendi. 12 izole policy
   testi ajanin elinde gecti; Android uygulama kimligi kontrolu
   **henuz `functions/index.js` handler'ina baglanmadi**.
2. `functions/test/api-route-boundary.test.js` icindeki yeni 3 "verified but
   untrusted app" reproducer'i **0 pass / 3 fail** verdi. Bu bilinen kirmizi
   sonuc saklandi; onceki 1267/0 backend sonucunu bu yeni kaynak icin gecerli
   sayma. Diger fixture App ID literalleri dogru Android ID'sine guncellendi.
3. Sonraki ilk kod isi: policy'nin kapsam/uyumluluk kararini incele, mevcut
   generic token dogrulamasini koruyarak sunucu handler'ina dar entegrasyonu
   tamamla, ucu da yesile donsun; sonra tum backend regresyonunu seri calistir.
   Bu aktarim turunda oyun/sunucu davranisi degistirilmedi.
4. V236 ekonomi/index/security kaynaklarinin canliya dagitildigi dogrulanmadi;
   bu turda deploy yapilmadi. 26 Ekim salt-okunur rollout kontrolunde V1
   matchmaking acik, maintenance kapali ve Android min build 17 idi. Bu degerler
   zamanla degisebilir; yeni oturumda tekrar oku. Store-ready flag'i false
   goruldu; gercek Play kabul kaniti olmadan sirf raporu yesillendirmek icin acma.
5. V236 APK build'i kesilmis gorunuyor; tamamlanmis guncel V236 APK/AAB yok.
   Eski `build/` ciktisini yeni kaynak saniip yayinlama. Son yuklenen Play
   versionCode'u kesinlestirilmedi; yeni release kodu musaitligi kontrol edilmeli.
6. Gercek Android cihaz, gercek Play Integrity/App Check tokeni, iki cihazli
   canli online mac, Google hesap geri yukleme ve Play billing/refund/RTDN
   uctan uca kabul edilmedi. Cihaz/FPS/isinma/uzun oturum testi de yapilmadi.

## Oncelik ve Koruma

- Once yukaridaki somut yarim backend patch'i ve guvenli online kabul akisi.
- Ardindan temiz kurulum -> loading -> LUNO selamlama -> uygulamali egitim ->
  ana menu -> AI -> iki hesapli online mac -> arka plan/geri donus -> sonuc.
- V236 orijinal sanat dosyalari, 24 kart, onayli mana/guc/ekonomi ve imzalama
  kimligi korunmali. Son kullanici onayi olmadan yeni balance/protokol degistirme.
- Gorsel calismada native Flutter kaynagini baz al; eski HTML ekranlarini
  yanlislikla guncel uygulama sanma. Var olan golden'lari gorsel incelemeden ezme.
- Bu aktarimdan "sifir bug", "tam yayina hazir" veya cihazda test edildi sonucu
  cikarma. Mevcut kabul karari **RELEASE HOLD**; bu bir GitHub aktarim engeli
  degil, oyun yayini icin kalan kabul kapilarinin durust kaydidir.
