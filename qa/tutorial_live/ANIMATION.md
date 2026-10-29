# Canlı tutorial Luno

Orijinal Luno çizimi Blender 5.2.3 içinde UV mesh ile hareketlendirildi: göz kırpma, küçük ağız hareketi, baş selamı ve el dalgası. ImageMagick/WebP ile 16 kare tek lossless 640×640 atlas oldu. Orijinal çizim ve V237/V238 kart atlasları değiştirilmedi. Kaynak Python betikleri `luno_chess/artwork/tutorial_live/` altında; `.blend`, frame’ler, kaynak hash’leri ve önizleme burada bulunur.

[Animasyon önizlemesi](animation/luno-live-preview.webp) kaynak hareketlerini gösterir; Android kaydı değildir. Uygulamadaki gesture 1100ms sürer; ardından 4700ms uyur. Yeni yönerge hemen tepkiyi başlatır; aynı cue rebuild’i süreyi ertelemez. Arka plan, örtülü rota, TickerMode, azaltılmış hareket ve dispose hem hareketi hem timer’ı durdurur. Resume eski yönergeyi tekrar oynatmaz. Azaltılmış harekette orijinal sabit portre kullanılır.

Atlas dosyası 324110B, mantıksal RGBA 1638400B (1.5625MiB). Bu, Android toplam RAM/GPU ölçümü değildir. Tek doku crop edilir;16 bağımsız decode veya yeni shader/video/animasyon paketi eklenmedi. Cihaz FPS/build-raster p95–p99 ve uzun maç ölçümleri NOT RUN.

Karşılama portresi büyütüldü. İlk maç yönergeleri önce tek taşı, sonra hedef kareyi, kart hedefini ve onayı sırayla açıklar. Feda/kart pası, seçimi kapatma, özel taş ve bitmiş deneme başlıkları mevcut kontrolle eşleşir. Öğrenme ilerlemesi, dört hamle/kart hedefleri, oyuncu özgürlüğü, kurallar ve ödüller korunur. Yeni konuşma kaydı/ses eklenmedi.

[screenshots/](screenshots/) güncel Flutter render’larıdır: TR/EN,320/430dp, büyük yazı ve tablet. `welcome-live-*` aktif göz kırpma, `welcome-*-step*` dinlenme/CTA örnekleri; `first-move-*` yalnız coach fixture’ı; `current-battle-target-*` varsa tam gerçek Flutter battle fixture’ıdır. Bunlar fiziksel Android kabulü değildir.
