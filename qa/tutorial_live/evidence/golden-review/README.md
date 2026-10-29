# Açık görsel karşılaştırmalar

Son tam koşuda 97 pixel testi FAIL kaldı. Aynı 97 test adının V240’ta da başarısız olduğu ve hepsinin gerçek pixel mismatch mesajı verdiği ayrı doğrulandı. Güncel 97 aday PNG, önceki V239 adaylarıyla byte-identical. Bu, mevcut çizimlerin onaylandığını veya eski referansların yanlış olduğunu kanıtlamaz.

Buradaki iki JSON, ajan incelemesinin sınırlı ara bulgularıdır; tam 97 görüntü için tasarım kabulü değildir. Yedi temsilî metrikten rehber ekranında geniş değişim görülür; yalnız metrikle bunun doğru/yanlış tasarım olduğuna karar verilmedi. Test yorumunda belirtilen eski `qa/v216/golden-review` onay kaydı bu aktarımda yoktur. Golden güncellenmedi ve assertion gevşetilmedi.

Nihai sınıflandırma: [test mesajları](../flutter/failure-classification.json), [güncel aday hash karşılaştırması](../flutter/golden-comparison.json). **Tam Flutter FAIL** ve **RELEASE HOLD** korunur.
