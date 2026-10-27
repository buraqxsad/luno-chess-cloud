# Online + Ödeme (IAP) — Senin Yapman Gerekenler

Bu iki özellik **sunucu/mağaza hesabı** ister; kodu hazır yazarım ama
senin config dosyaların olmadan derlenmez. Sırayla git, sonra bana "hazır" de.

---

## A) ONLINE (Firebase) — eşleşme, arkadaş, DM

HTML sürümün zaten Firebase kullanıyor; aynı projeyi Flutter'a bağlayacağız.

### Adımlar
1. Terminalde FlutterFire CLI:
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   → Mevcut Firebase projeni seç (HTML'in kullandığı). Bu, `lib/firebase_options.dart`
   ve Android/iOS config dosyalarını **otomatik** üretir.
2. Bana haber ver — şu paketleri ekleyip online katmanı yazacağım:
   `firebase_core`, `firebase_auth`, `firebase_database`.
3. Realtime Database kuralları: repodaki **`database.rules.json`** (kökte) zaten
   hazır — Firebase Console → Realtime Database → Rules'a yapıştır + Publish.

### Online mimari (yazılacak)
- `OnlineService` arayüzü: giriş (Google/e-posta), eşleşme kuyruğu, oda,
  hamle/kart aktarımı (`acts` relay), otoriter `result` düğümü.
- Maç ekranı online modda `MatchState`'i karşı tarafın aksiyonlarıyla senkronlar
  (motor zaten otoriter-sunucuya hazır kurgulandı).
- **FAZ 2 (güvenlik):** kupa/altın/elmas Cloud Functions'a taşınır (istemci yazamaz).

---

## B) IAP (Native Faturalandırma) — elmas/paket satışı

Dijital para (elmas) için Google Play / Apple **kendi faturalandırmasını zorunlu** tutar.

### Önerilen: RevenueCat
Abonelik (premium) + makbuz doğrulamasını hazır verir, Android+iOS tek entegrasyon.
1. https://www.revenuecat.com → ücretsiz hesap, uygulama oluştur.
2. **Google Play Console**'da ürünleri tanımla:
   - Tüketilir: `gems_starter` (29,99₺), `gems_pro` (119₺) … (oyundaki paketler)
   - Abonelik: `premium_monthly`, `premium_yearly`
3. RevenueCat'e bu ürünleri bağla, API anahtarını al.
4. Bana anahtarı ver — `purchases_flutter` paketini ekleyip MAĞAZA'daki
   "Elmas Paketleri" + Premium butonlarını gerçek satın almaya bağlayacağım.
5. **Sunucu doğrulama:** RevenueCat webhook → Cloud Function → elması sunucuda ver
   (sahte satın almayı engeller).

### Alternatif: doğrudan Play Billing
`in_app_purchase` paketiyle kesintisiz ama makbuz doğrulama + abonelik mantığını
biz yazarız (daha riskli). İlk lansman için RevenueCat önerilir.

---

## ÖZET
| Özellik | Sen yap | Ben yaparım |
|---|---|---|
| Online | `flutterfire configure` + DB rules publish | online katman kodu |
| IAP | RevenueCat/Play Console ürünleri + API anahtarı | satın alma kodu |

İkisi de hazır olunca tek tek bağlarız. Şimdilik oyun çevrimdışı tam oynanır.
