# LUNO Chess - Bulut Codex Devir Notu

Son dogrulama/aktarim tarihi: 27 Ekim 2026. Bu dosya kaynak aktarimini anlatir;
oyunun kusursuz, canli servislerin tamamen kabul edilmis veya Play yayininin
onaylanmis oldugu anlamina gelmez.

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
