# Sistem kapsamı

Bu tablo son gerçek test sonuçlarını alanlara bağlar. Alanlar örtüşür; dosya/test sayıları toplanmaz. Bir test adının alanla eşleşmesi bütün davranışların kabul edildiği anlamına gelmez.

| Alan | Backend dosyası | Flutter dosyası | Gerçek servis/cihaz |
| --- | ---: | ---: | --- |
| Hesap, silme ve oturum | 24 | 49 | Kabul edilmedi |
| Ekonomi, ödül ve ödeme | 24 | 29 | Kabul edilmedi |
| Online, arkadaşlık ve mesaj | 21 | 47 | Kabul edilmedi |
| Savaş, kartlar ve gizlilik | 5 | 85 | Kabul edilmedi |
| Kurallar ve kayıt biçimleri | 7 | 21 | Kabul edilmedi |
| Tutorial, rehber ve arayüz | 1 | 88 | Kabul edilmedi |
| Güvenlik ve API sınırları | 18 | 8 | Kabul edilmedi |

[Dosya ve sonuçlar](system-coverage.json). [Yeni hata/düzeltme kanıtları](BUGS.md), [24 kart](cards/acceptance.md) ve [açık kapılar](GATES.md) kapsam sınırlarını gösterir. Ayarlar, ses ve yasal/native wrapper kaynak incelemesinde bu tur ek bir doğrulanmış kusur bulunmadı; Android etkileşim ve fiziksel ses testi yapılmadı.
