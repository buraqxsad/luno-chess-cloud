# Korunan 24 kart — son kaynak kabul matrisi

Son tam koşunun `v239_card_acceptance_test.dart` dosyası **76/76** geçti. Aşağıdaki her satır, gerçek Flutter `BattleV1Screen` üzerinde doğru kart/atlas/hedef, tekrar olay, mantıksal ses zamanı, background/resume ve ayrı timeout/resign testlerinin sonucudur. Server transport fixture’dır. Güncel çalışmanın dili varsayılan TR; seçilmiş EN koşusu bu takipte yeniden çalıştırılmadı. [Tarihsel V240 TR/EN ekranları ve sınırları](../../v240/cards/acceptance.md) korunur. Bunlar Android cihaz kabulü değildir.

| Kart | Atlas | Güncel TR Flutter | Güncel ayrı EN koşusu | Native Android / GPU / fiziksel ses |
| --- | --- | --- | --- | --- |
| radar | arcane | PASS | NOT RUN | NOT RUN |
| prophecy | veil | PASS | NOT RUN | NOT RUN |
| shelter | crystal | PASS | NOT RUN | NOT RUN |
| chain | binding | PASS | NOT RUN | NOT RUN |
| slow | binding | PASS | NOT RUN | NOT RUN |
| pawn_deviation | arcane | PASS | NOT RUN | NOT RUN |
| pawn_advance | crystal | PASS | NOT RUN | NOT RUN |
| locked_square | binding | PASS | NOT RUN | NOT RUN |
| freeze | crystal | PASS | NOT RUN | NOT RUN |
| purify | crystal | PASS | NOT RUN | NOT RUN |
| mine | binding | PASS | NOT RUN | NOT RUN |
| break_seal | binding | PASS | NOT RUN | NOT RUN |
| fog | veil | PASS | NOT RUN | NOT RUN |
| mana_sabotage | veil | PASS | NOT RUN | NOT RUN |
| card_block | binding | PASS | NOT RUN | NOT RUN |
| rook_bend | binding | PASS | NOT RUN | NOT RUN |
| angry_n | crystal | PASS | NOT RUN | NOT RUN |
| shadow_pass | veil | PASS | NOT RUN | NOT RUN |
| hunt_vow | binding | PASS | NOT RUN | NOT RUN |
| watch_vow | arcane | PASS | NOT RUN | NOT RUN |
| echo | veil | PASS | NOT RUN | NOT RUN |
| fate_exchange | veil | PASS | NOT RUN | NOT RUN |
| shadow_contract | veil | PASS | NOT RUN | NOT RUN |
| board_seal | binding | PASS | NOT RUN | NOT RUN |

Aynı son tam koşuda V220 normal/reduced-motion ve iki oyuncu yönü:97/97; V226 semantik:320/320; V238 choreography:3/3 ve capture:6/6. Shelter rok/terfi/yakalanma ve üç hızlı cast kontrolleri V239’un 76 testine dahildir. Her kart × her özel hamle kombinasyonu denenmedi. [Makine özeti](acceptance.json); tam ham log `../logs/flutter-full.jsonl.gz` içindedir.

V237/V238 atlaslarının ve önceki varlıkların baytları değişmedi. Yeni tek asset tutorial portre atlasıdır. Paket denetimi tüm 750 asset’i kaynakla birebir karşılaştırdı.
