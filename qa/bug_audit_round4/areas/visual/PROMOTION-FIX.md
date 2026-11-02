# Güncel Türkçe arena başlığı — P2 düzeltildi

ArenaPromotionHeading yalnız Cinzel-latin seçiyor, CinzelTurkish alt kümesini fallback olarak eklemiyordu. TR temadan kalan Spectral-latin de İ/Ş/Ğ gliflerini içermiyor. font-cmap.json gerçek bundled fontların cmap kanıtıdır. Başlık güncel Flutter raster’ında P□YON VAD□S□ görünüyordu; eski golden da aynı kusuru içeriyordu. Native OS fallback davranışı ölçülmedi.

Bağımsız desteklenen font zinciriyle güncel heading raster’ını karşılaştıran üç test: **önce1pass/2fail**, bir satırlık mevcut CinzelTurkish fallback düzeltmesi sonrası **3/3**. Aynı koşuda eski progression testleriyle **39/39**. İngilizce kontrol değişmez; büyük yazıda Ş/Ğ/İ de doğru çizilir. Yeni font/asset eklenmedi.

Full promotion ekranı ayrıca tekrar render edildi. Önceki R3 actual ile yeni actual farkı yalnız (99,91)–(291,126) başlık bölgesinde2045pixel; diğer tüm pikseller aynıdır. Yeni/önceki tam ekranlar ve mevcut referans görseli root tarafından incelendi. `approved-visual-candidates.json` yalnız bu tam PNG’nin exact hash’ini tanır. **Golden güncellenmedi;97tarihsel görselFAIL gizlenmedi.** Önceki bir yanlış font-path ve fake-async raster bekleme denemesi test düzeneği hatası olarak saklandı; ürün hatası veya PASS sayılmadı.

Commitfc336b7. All97 görsel incelemenin MATRIX/result dosyaları ayrı okuma çalışmasıdır; metin-kenarı farkları ve eksik tasarım/font referansı için genel kabul verilmedi.
