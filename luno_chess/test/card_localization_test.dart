import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/cards/card_catalog.dart';
import 'package:luno_chess/cards/card_def.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/widgets/card_info.dart';

void main() {
  const en = LunoLocalizations(Locale('en'));
  const tr = LunoLocalizations(Locale('tr'));
  test('all 29 card names and descriptions have English copy', () {
    expect(kCards.length, 29);
    for (final card in kCards.values) {
      for (final copy in [card.name, card.desc]) {
        expect(en.translate(copy), isNot(copy), reason: card.key);
        expect(en.translate(copy).trim(), isNotEmpty);
        expect(tr.translate(copy), copy);
      }
    }
  });
  test('all card targets and rarities are localized', () {
    for (final target in CardTarget.values) {
      final copy = cardTargetLabel(target);
      expect(en.translate(copy), isNot(copy));
    }
    for (final rarity in CardRarity.values) {
      final copy = rarityLabel(rarity);
      expect(en.translate(copy), isNot(copy));
    }
    expect(en.cardLevel(2, 3), 'Lv2 (max 3)');
    expect(tr.cardLevel(2, 3), 'Sv2 (en fazla 3)');
  });
}
