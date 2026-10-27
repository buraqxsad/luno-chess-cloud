# Luno Chess (Flutter) — Nasıl Çalıştırılır

> Guncellik notu (2026-09-08): Asagidaki ozellik ve 25-test listesi ilk
> prototipten kalmistir; guncel durum veya yayin hazirligi kaniti degildir.
> Firebase online entegrasyonu artik kaynak kodda mevcuttur. Guncel mimari,
> test kanitlari ve cihaz/Play kontrol sinirlari icin
> [CODEX_HANDOFF.md](audit/CODEX_HANDOFF.md) dosyasini kullanin.

Oyunun **tam native Flutter** sürümü. Çevrimdışı oyun **özellik-tam ve test edildi**.
Online + ödeme, senin Firebase/mağaza hesaplarını gerektirir (aşağıda).

---

## Gereksinim: Flutter SDK (bir kez)
1. Flutter SDK: https://docs.flutter.dev/get-started/install
2. Android Studio → **Plugins** → **Flutter** (Dart otomatik gelir).
3. `flutter doctor` → Android toolchain + emülatör/telefon yeşil olmalı.

## Çalıştırma
```
cd luno_chess
flutter pub get
flutter run
```
Veya Android Studio → **Open** → `luno_chess` → cihaz seç → **Run ▶**.

---

## Şu an ÇALIŞAN + TEST EDİLEN (çevrimdışı)
- ✅ **Satranç motoru** — perft doğrulandı (20/400/8902/197281)
- ✅ **AI rakip** — 6 zorluk (Bebek→Efsane), minimax + alpha-beta
- ✅ **29 kart + mana + efektler** — fuzz 300 maç, 29/29 kart, 0 hata
- ✅ **Maç ekranı** — kart eli, mana, hedefleme, seviye seçici, efekt rozetleri
- ✅ **DESTE** — 6 yuvalı deste kurma + altınla kart yükseltme
- ✅ **MAĞAZA** — günlük ödül, altın/elmas sandık, koleksiyon
- ✅ **LUNO PASS** — 30 seviye bedava+premium şerit (elmasla premium)
- ✅ **PROFİL** — para/kupa/koleksiyon + istatistikler
- ✅ **REHBER** + kart bilgi kartı (karta uzun bas)
- ✅ Kalıcı kayıt (shared_preferences) — altın/elmas/deste/profil saklanır

**Test durumu:** 25/25 birim+widget testi, perft + kart fuzz + AI-vs-AI sim — hepsi temiz.

### Geliştiricinin doğrulama araçları (opsiyonel)
```
dart run tool/selfcheck.dart   # satranç motoru perft
dart run tool/cardsim.dart 300 # kart sistemi fuzz self-play
dart run tool/aisim.dart 25    # AI-vs-AI entegrasyon
flutter test                   # tüm testler
```

---

## KALAN: Online + Ödeme (senin hesapların gerekiyor)
Bunlar sunucu/mağaza hesabı istediği için kodu hazır yazıp **senin
config'inle** bağlayacağız. Bkz: `ONLINE_VE_IAP_KURULUM.md`.
1. **Firebase (online)** — `flutterfire configure` ile kendi projeni bağla.
2. **IAP (faturalandırma)** — RevenueCat + Play Console / App Store.

Hazır olduğunda config'i ver, online maç + mağaza ödemesini bağlayalım.
