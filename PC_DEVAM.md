# LUNO Chess — bilgisayardan devam için son bulut devri

5 Kasım 2026. Dal: `codex/cloud-transfer-20261027`.
Son uygulama/backend kaynak commit’i: `767ae74314a664f180ad1ca9e279e2c9881989d2`.
Bundan sonraki devir commit’i yalnız belge ve QA kanıtı ekler.
Aktif Flutter projesi `luno_chess/`; sunucu `functions/`, motor TS `functions/rules-v1/`.
Kök HTML ve `luno_android/` mevcut uyumluluk girdileridir.

## Aktarım: GitHub erişimi engelli; ZIP veya bundle kullan

5 Kasım'daki yükleme denemesi `Invalid username or token` ile reddedildi;
GitHub API de `401 Bad credentials` döndürdü. Son bulut commit'leri GitHub'a
yüklenemedi. GitHub dalını çekmek tek başına bu devri getirmez.

İndirilen **Luno-Chess-final-source.zip** dosyasını mevcut PC projesinin üzerine
yazmadan ayrı klasöre aç. ZIP, son kaynakları ve takipli assetleri içerir;
Git geçmişi, toolchain/cache ve yerel imzalama sırlarını içermez.
Git geçmişini de aktarmak için **Luno-Chess-final-source.bundle** kullanılabilir;
mevcut klonda `14780e10e9b511aababd009517507425890c4840` temel commit'i gerekir.
Önce `git bundle verify` ile doğrula, sonra ayrı inceleme dalına fetch et.
Yeni klasöre mevcut yerel ayarları/anahtarları taşırken sırları Git'e ekleme.
GitHub yeniden yetkilendirildiğinde bu kaynak ayrıca yüklenebilir.

## Önce okunacaklar

- [DEVAM.md](DEVAM.md): önceki sürümler ve tarihsel düzeltmeler.
- [Son gerçek sonuçlar](qa/bug_audit_round5/REPORT.md), [sekiz kusur](qa/bug_audit_round5/BUGS.md),
  [açık kapılar](qa/bug_audit_round5/GATES.md), [24 kart matrisi](qa/bug_audit_round5/cards/acceptance.md).
- [Aktarım durumu](qa/bug_audit_round5/HANDOFF-STATUS.json).

## Mevcut durum

Sekiz somut kusur kapatıldı: alınmış Premium Pass’in eski sezon okumasıyla silinmesi;
yarım grant sonrası refund; boş ürün kataloğunun retry edilememesi; eski pending
sahiplik yanıtı; özel kart satır/Confirm callback’i; sonuç ACK/cleanup yarışı;
eski V1 maç geçmişinin hesap silmede kalması; legacy settlement’ın silinmiş özel veriyi geri yazması.
İkisi yeni P2 aile, altısı mevcut ailelerde yeni yol (1 P1 + 5 P2).

Son tam koşu aynı kaynakta:

| Kontrol | Gerçek sonuç |
| --- | --- |
| Flutter analiz | Temiz |
| Flutter, 448 dosya | 11.881 geçti / 97 eski görsel başarısızlık / 0 atlandı |
| Backend, 104 dosya | 1.481 geçti / 0 başarısız / 1 atlandı |
| TypeScript | 376 geçti / 0 başarısız |
| Dart/TS differential | 3.101 senaryo / 10.967 durum, 0 ayrışma |
| Son gerçek yerel RTDB/Admin SDK | 7 geçti / 2 başarısız; **FAIL/NOT COMPLETE** |
| Yeni ARM64 debug APK | İmza, 750 asset, paket kimliği ve statik 16 KB denetimi geçti |

97 görsel adayın tamamı R4 ile aynı baytlar; golden referansları değiştirilmedi.
Tam Flutter sonucu FAIL olarak korunur. Görüntüleri incelemeden golden güncelleme,
geçerli assertion’ı zayıflatma veya testi silerek geçirme.

## İlk dar kapsamlı iş

İki SDK senaryosu `enqueueBattleV1` ve `createFriendlyRoom` başlangıcında
`INVALID_ACTION`/400 aldı; silme assertion’larına ulaşmadı. Ürün/harness ayrımı yapılmadı.
[Ham sonuç](qa/bug_audit_round5/local-sdk-summary.json) ve
[as-run harness](qa/bug_audit_round5/areas/runtime-billing/fences.cjs) incelensin.

Muhtemel kurulum farkı: fixture `battleRollout/config` altına `LEGACY_ONLY` nesnesini
ham yazıyor; içindeki boş `forceUpdatePlatforms: []` gerçek RTDB’de kaybolabilir,
bellek adaptörü ise korur. Sunucunun `decodeConfig` yolu `configJson` JSON zarfını
zaten destekler. Önce bu iki fixture’ın gerçek DB şemasını kontrol et; gerekiyorsa
`{configJson: JSON.stringify(config)}` biçimiyle düzelt ve yalnız bu senaryoları
tekrar çalıştır. Bu neden henüz yeniden koşuyla doğrulanmadı. Uygulama doğrulamalarını
zayıflatma, 7/9 sonucunu 9/9 diye raporlama. Test verisi yalnız `demo-*` localhost
namespace’inde kalsın; üretim Firebase kullanılmasın.

Bulut harness’leri `/workspace/...` yolları içerir; PC’deki repo/SDK yollarına uyarlanmalıdır.
`fixed-index.cjs` as-run kopyası pakete eklenmez; Git’teki kaynak commit’inden veya
aynı SHA256 doğrulanan `functions/index.js` dosyasından üretilebilir.
Kaynak/test değişmedikçe saatler süren tüm koşuyu tekrar başlatma; önce ilgili dar testleri kullan.

## Araç sürümleri ve koruma

Projeyi sürüm yükselterek uyarlama. Kullanılan sürümler: Flutter 3.47.1, Dart 3.13.1,
Java 21.0.12, Node 22.23.3, Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20,
NDK 28.2.13676358, targetSdk 36. FVM/proje ayarlarını ve PC’deki mevcut araçları kontrol et.
Cloud `/workspace/toolchains/luno-env.sh` PC’de bulunmak zorunda değildir.
24 kartın kurallarını, V237/V238 animasyonlarını, sanat/atlasları, oyuncu haklarını,
önceki V235–V240 düzeltmelerini koru.

Mevcut PC çalışma ağacını ve yerel değişiklikleri önce incele/koru; devri ayrı inceleme
branch/worktree veya klasörde aç. Mevcut imzalama dosyalarını kullan; keystore,
key.properties, şifre veya auth tokenlarını Git’e koyma. Bulutta upload key yoktu;
release anahtarı oluşturulmadı/değiştirilmedi.

## Açık kabul kapıları — RELEASE HOLD

- Önceki API29 native raster/libflutter.so SIGSEGV çözümü doğrulanmadı.
- Güncel APK ile gerçek Android oyuncu yolculuğu, FPS/RAM/build-raster p95–p99,
  uzun maç ve gerçek 16 KB runtime kabulü yapılmadı. Widget görüntüsü fiziksel cihaz değildir.
- Gerçek Firebase/Auth/Google/App Check/Integrity ve Play lisans Billing/Console/Pre-launch kabulü yok.
- Release upload keystore/properties eksik; release APK/AAB üretilmedi.
  VersionCode 19’un Play geçmişi bilinmiyor.
- Yeni güvenlik ajanı probe’u otomatik içerik filtresinde BLOCKED; geçerli 4-case
  sonucu yok. Scratch/ilk hatalı koşu dış kanıtta korundu, yeniden çalıştırılmadı,
  geçerli eski testler kaldırılmadı. Ayrıntı `areas/security/BLOCKED.json`.
- Tarihsel silme taraması sayfalı/cooperative zaman bütçeli; büyük üretim veri kümesi
  performansı ve worker crash-recovery pencereleri tam kabul edilmedi.

Sunucu değişiklikleri canlıya dağıtılmadı. Gerçek ödeme, Firebase deploy, Play upload
ve kamuya açık oyun yayını yapılmasın; kullanıcı bunları ayrıca yetkilendirmedi.
GitHub’a bu devir kaynağının yüklenmesi kullanıcı tarafından istendi.

Bulut ortamı kaybolup yeniden bağlandı; tamamlanmış loglar sonradan kontrol edildi.
Geçici durmuş emulator RAM arşivi orijinal 1.426.527.045 bayt/SHA256 ile geri kondu,
arşiv silindi. Emulator açılmadı; toolchain veya oyun kaynağı bu sebeple eksiltilmedi.
