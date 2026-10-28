import '../battle_v1/model.dart';
import '../widgets/luno_arcane_halo.dart';

/// Fixed public artwork selection, never inferred from private card contents.
enum BattleSpellMotif {
  arcane(LunoArcaneHalo.asset),
  crystal('assets/native_art/v238-crystal-atlas.webp'),
  binding('assets/native_art/v238-binding-atlas.webp'),
  veil('assets/native_art/v238-veil-atlas.webp');

  const BattleSpellMotif(this.asset);
  final String asset;
}

BattleSpellMotif battleSpellMotif(CardId card) => switch (card) {
  CardId.shelter ||
  CardId.freeze ||
  CardId.purify ||
  CardId.pawnAdvance ||
  CardId.angryN => BattleSpellMotif.crystal,
  CardId.chain ||
  CardId.slow ||
  CardId.lockedSquare ||
  CardId.mine ||
  CardId.breakSeal ||
  CardId.cardBlock ||
  CardId.rookBend ||
  CardId.huntVow ||
  CardId.boardSeal => BattleSpellMotif.binding,
  CardId.prophecy ||
  CardId.fog ||
  CardId.manaSabotage ||
  CardId.shadowPass ||
  CardId.echo ||
  CardId.fateExchange ||
  CardId.shadowContract => BattleSpellMotif.veil,
  CardId.radar ||
  CardId.pawnDeviation ||
  CardId.watchVow => BattleSpellMotif.arcane,
};
