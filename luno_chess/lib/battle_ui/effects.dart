import 'package:flutter/material.dart';
import '../battle_v1/model.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import 'art.dart';

String boardEffectArt(BoardEffectType type) => switch (type) {
  BoardEffectType.mine => 'mine',
  BoardEffectType.lockedSquare => 'locked-square',
  BoardEffectType.fog => 'fog',
  BoardEffectType.boardSeal => 'board-seal',
};
String pieceEffectArt(PieceEffectType type) => switch (type) {
  PieceEffectType.shelter => 'shelter',
  PieceEffectType.chain => 'chain',
  PieceEffectType.slow => 'slow',
  PieceEffectType.freeze => 'freeze',
  PieceEffectType.mineDebuff => 'mine',
};
CardId boardEffectCard(BoardEffectType type) => switch (type) {
  BoardEffectType.mine => CardId.mine,
  BoardEffectType.lockedSquare => CardId.lockedSquare,
  BoardEffectType.fog => CardId.fog,
  BoardEffectType.boardSeal => CardId.boardSeal,
};
CardId pieceEffectCard(PieceEffectType type) => switch (type) {
  PieceEffectType.shelter => CardId.shelter,
  PieceEffectType.chain => CardId.chain,
  PieceEffectType.slow => CardId.slow,
  PieceEffectType.freeze => CardId.freeze,
  PieceEffectType.mineDebuff => CardId.mine,
};

class BattleFloorEffects extends StatelessWidget {
  final RuleState rules;
  final PieceColor viewer;
  final int square;
  const BattleFloorEffects({
    super.key,
    required this.rules,
    required this.viewer,
    required this.square,
  });
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        for (final effect in rules.boardEffects.where(
          (e) => e.squares.contains(square),
        ))
          if (effect.type == BoardEffectType.fog ||
              effect.type == BoardEffectType.boardSeal)
            _ZoneCell(
              key: ValueKey('effect-${effect.id}-$square'),
              effect: effect,
              viewer: viewer,
              square: square,
            )
          else
            Align(
              alignment:
                  effect.type == BoardEffectType.mine
                      ? Alignment.bottomLeft
                      : Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: BattleArt(
                  boardEffectArt(effect.type),
                  key: ValueKey('effect-${effect.id}-$square'),
                  size: effect.type == BoardEffectType.mine ? 22 : 30,
                ),
              ),
            ),
        for (final vow in rules.vows.where((v) => v.square == square))
          Align(
            alignment: Alignment.bottomRight,
            child: BattleArt('vow', key: ValueKey('vow-${vow.id}'), size: 20),
          ),
      ],
    ),
  );
}

class _ZoneCell extends StatelessWidget {
  final BoardEffectInstance effect;
  final PieceColor viewer;
  final int square;
  const _ZoneCell({
    super.key,
    required this.effect,
    required this.viewer,
    required this.square,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final files = effect.squares.map(Square.fileOf).toList()..sort();
      final ranks = effect.squares.map(Square.rankOf).toList()..sort();
      final col =
          viewer.isWhite
              ? Square.fileOf(square) - files.first
              : files.last - Square.fileOf(square);
      final row =
          viewer.isWhite
              ? ranks.last - Square.rankOf(square)
              : Square.rankOf(square) - ranks.first;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: box.maxWidth * 2,
          maxHeight: box.maxHeight * 2,
          child: Transform.translate(
            offset: Offset(-col * box.maxWidth, -row * box.maxHeight),
            child: Opacity(
              opacity: effect.type == BoardEffectType.fog ? .25 : .65,
              child: SizedBox(
                width: box.maxWidth * 2,
                height: box.maxHeight * 2,
                child: BattleArt(boardEffectArt(effect.type), fit: BoxFit.fill),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class BattlePieceEffects extends StatelessWidget {
  final RuleState rules;
  final int square;
  final bool aurasOnly;
  const BattlePieceEffects({
    super.key,
    required this.rules,
    required this.square,
    this.aurasOnly = false,
  });
  @override
  Widget build(BuildContext context) {
    final effects =
        rules.pieceEffects
            .where((e) => e.pieceId == rules.pieceIds[square])
            .toList();
    final vows = rules.vows.where(
      (v) => v.pieceId != null && v.pieceId == rules.pieceIds[square],
    );
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (aurasOnly)
            for (final effect in effects.where(
              (e) =>
                  e.type == PieceEffectType.shelter ||
                  e.type == PieceEffectType.freeze,
            ))
              Opacity(
                opacity: .65,
                child: BattleArt(
                  effect.type == PieceEffectType.shelter
                      ? 'board-shelter'
                      : 'board-freeze',
                  key: ValueKey('piece-effect-${effect.id}'),
                ),
              ),
          if (!aurasOnly)
            Align(
              alignment: Alignment.topRight,
              child: Wrap(
                spacing: 1,
                children: [
                  for (final effect in effects.where(
                    (e) =>
                        e.type != PieceEffectType.shelter &&
                        e.type != PieceEffectType.freeze,
                  ))
                    BattleArt(
                      pieceEffectArt(effect.type),
                      key: ValueKey('piece-effect-${effect.id}'),
                      size: 14,
                    ),
                  for (final vow in vows)
                    BattleArt('vow', key: ValueKey('vow-${vow.id}'), size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
