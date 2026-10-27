import 'package:flutter/material.dart';
import '../battle_ui/board.dart';
import '../battle_v1/authoritative.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';

/// Uses the actual battle renderer and immutable canonical starting position.
/// There is no preview-only piece/square resolver and no gameplay mutation.
class CosmeticMatchPreview extends StatelessWidget {
  const CosmeticMatchPreview({super.key, required this.setId,
    this.side = PieceColor.white});
  final String setId;
  final PieceColor side;
  static final _position = DeckManager.newBattle(
    white: starterDeck, black: starterDeck);

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 416),
      child: RepaintBoundary(
        child: BattleBoard(
          key: ValueKey('costume-match-$setId-${side.name}'),
          view: _position.view(side),
          pieceSet: setId,
          enabled: false,
          onTap: (_) {},
        ),
      ),
    ),
  );
}
