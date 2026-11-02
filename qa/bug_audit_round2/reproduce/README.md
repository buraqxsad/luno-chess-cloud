# Yeniden doğrulama

Bu dizindeki betikler kayıtlı worker yollarını kullanır. Başka makinede yolların uyarlanması gerekir. Kaynak commit’i `../source.json` içindedir. Kullanılan sürümler: Flutter 3.47.1, Dart 3.13.1, OpenJDK 21.0.12, Node 22.23.3. Toolchain aktivasyonu `/workspace/toolchains/luno-env.sh` idi; proje güncellenmedi.

1. Alan raporları her kusur için önceki başarısız tekrar üretimi, kaynak hash’ini ve düzeltilmiş sonucu açıklar. Yeni regresyon testleri repodaki commit’lerdedir.
2. `run_node_direct.py` gerçek TAP case sayılarını toplar. Worker’ın dosya seviyesindeki PASS çıktısı assertion kanıtı sayılmaz.
3. `run_flutter_final.sh` analizi ve tam Flutter koşusunu çalıştırır. `summarize.py` başarılı gizli yükleyici olaylarını saymaz; başarısızlıkları saklar. Yalnız yeni oluşturulan untracked çıktılar dış kanıt dizinine taşınır; arşivlenen iki generated inventory, doğrulanmış test öncesi baytlarına döndürülür. Golden güncellenmez.
4. `post_tests.py`, yalnız test adı ve gerçek pixel hata mesajı önceki sonuçla eşleşen 97 farkı sınıflandırır; her aday görüntünün eski V239 baytlarına eşitliğini ayrıca doğrular. Bu eşitlik görsel tasarım onayı değildir.
5. Android build ve audit betikleri APK kimliği, aynı sertifika, kaynak asset baytları, ELF/ZIP statik 16 KB hizalamasını doğrular. Canonical APK dış teslim dizinindedir. Native Android, üretim Firebase ve gerçek Play testleri bu betiklerin kapsamı değildir.

Ham loglar `../logs/` altında gzip olarak bulunur. Alan logları ayrıca ilgili alan dizininde `.log.gz` adıyla korunur. Yerel SDK koşusunun bilinçli in-memory transport değişikliği ve Google fake kapsamı `../areas/runtime/REPORT.md` içinde açıklanır. Geçmiş başarısız koşular başarı sayılmaz. İncelenmemiş golden referansları değiştirilmez.
