# V240 — 24 kart animasyonu

PASS yalnız belirtilen widget kapsamını gösterir. Gerçek BattleV1Screen kullanılır; server transport fixture’dır. Native 24 kart/uzun maç/duyulan ses kabulü tamamlanmadı.

| Kart | Atlas | TR/EN güncel ekran | Yerel kabul | Gerçek Android |
| --- | --- | --- | --- | --- |
| radar | arcane | [TR](../screenshots/cards/tr/radar/impact.png) / [EN](../screenshots/cards/en/radar/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| prophecy | veil | [TR](../screenshots/cards/tr/prophecy/impact.png) / [EN](../screenshots/cards/en/prophecy/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| shelter | crystal | [TR](../screenshots/cards/tr/shelter/impact.png) / [EN](../screenshots/cards/en/shelter/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| chain | binding | [TR](../screenshots/cards/tr/chain/impact.png) / [EN](../screenshots/cards/en/chain/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| slow | binding | [TR](../screenshots/cards/tr/slow/impact.png) / [EN](../screenshots/cards/en/slow/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| pawn_deviation | arcane | [TR](../screenshots/cards/tr/pawn_deviation/impact.png) / [EN](../screenshots/cards/en/pawn_deviation/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| pawn_advance | crystal | [TR](../screenshots/cards/tr/pawn_advance/impact.png) / [EN](../screenshots/cards/en/pawn_advance/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| locked_square | binding | [TR](../screenshots/cards/tr/locked_square/impact.png) / [EN](../screenshots/cards/en/locked_square/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| freeze | crystal | [TR](../screenshots/cards/tr/freeze/impact.png) / [EN](../screenshots/cards/en/freeze/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| purify | crystal | [TR](../screenshots/cards/tr/purify/impact.png) / [EN](../screenshots/cards/en/purify/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| mine | binding | [TR](../screenshots/cards/tr/mine/impact.png) / [EN](../screenshots/cards/en/mine/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| break_seal | binding | [TR](../screenshots/cards/tr/break_seal/impact.png) / [EN](../screenshots/cards/en/break_seal/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| fog | veil | [TR](../screenshots/cards/tr/fog/impact.png) / [EN](../screenshots/cards/en/fog/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| mana_sabotage | veil | [TR](../screenshots/cards/tr/mana_sabotage/impact.png) / [EN](../screenshots/cards/en/mana_sabotage/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| card_block | binding | [TR](../screenshots/cards/tr/card_block/impact.png) / [EN](../screenshots/cards/en/card_block/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| rook_bend | binding | [TR](../screenshots/cards/tr/rook_bend/impact.png) / [EN](../screenshots/cards/en/rook_bend/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| angry_n | crystal | [TR](../screenshots/cards/tr/angry_n/impact.png) / [EN](../screenshots/cards/en/angry_n/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| shadow_pass | veil | [TR](../screenshots/cards/tr/shadow_pass/impact.png) / [EN](../screenshots/cards/en/shadow_pass/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| hunt_vow | binding | [TR](../screenshots/cards/tr/hunt_vow/impact.png) / [EN](../screenshots/cards/en/hunt_vow/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| watch_vow | arcane | [TR](../screenshots/cards/tr/watch_vow/impact.png) / [EN](../screenshots/cards/en/watch_vow/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| echo | veil | [TR](../screenshots/cards/tr/echo/impact.png) / [EN](../screenshots/cards/en/echo/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| fate_exchange | veil | [TR](../screenshots/cards/tr/fate_exchange/impact.png) / [EN](../screenshots/cards/en/fate_exchange/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| shadow_contract | veil | [TR](../screenshots/cards/tr/shadow_contract/impact.png) / [EN](../screenshots/cards/en/shadow_contract/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |
| board_seal | binding | [TR](../screenshots/cards/tr/board_seal/impact.png) / [EN](../screenshots/cards/en/board_seal/impact.png) | PASS, aşağıdaki sınırlar | BLOCKED |

Her kartta doğru kimlik/atlas/hedef, duplicate ve background/resume, timeout/resign ve mantıksal ses gecikmesi kontrol edildi. V220:24×iki yön×normal/reduced96altı aşamalı gerçek ekran vakası. Beş özel hareketli kartta taş kimliği/hedef takibi; Shelter’da rok/terfi/yakalanma. Bütün kart×hamle kombinasyonları NOT RUN. Hotseat/account-switch ortak yaşam döngüsü testlerinde; bütün özel pencere permütasyonları ayrıca denenmedi. Üç hızlı cast PASS; bütün kart çiftlerinin çapraz çarpımı NOT RUN. Fiziksel ses gecikmesi ve GPU texture belleği ölçülmedi. Ayrıntılı satır kapsamı JSON/CSV’dedir.
