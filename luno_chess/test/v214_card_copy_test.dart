import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/core.dart';
import 'package:luno_chess/battle_v1/local_clock.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/board.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/battle_learning_copy.dart';
import 'package:luno_chess/i18n/battle_v1_copy.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';

const _white = PieceColor.white;
const _black = PieceColor.black;

// Pin the important exceptions, not an exact prose snapshot.
const _criticalCopy = <CardId, (List<String>, List<String>)>{
  CardId.radar: (
    ['yalnızca sen', '"Elde değil"', '"elde"', 'garanti'],
    ['Only you', '"not in hand"', '"in hand"', 'guarantee'],
  ),
  CardId.prophecy: (
    [
      'en fazla 2',
      'normal kart çekişi değildir',
      'eline kart eklemez',
      'onaylayınca',
    ],
    ['up to 2', 'not a normal draw', 'adds no card', 'Confirming'],
  ),
  CardId.shelter: (
    ['Şah dışındaki', 'doğrudan', 'kart aşaması kapanınca', 'Mayın'],
    ['non-king', 'directly', 'closes their next card phase', 'Mine'],
  ),
  CardId.chain: (
    ['geçerken alma', 'hangi taşını', 'Arındırma', 'boş kareye'],
    ['en passant', 'different piece', 'Purify', 'empty destination'],
  ),
  CardId.slow: (
    ['fil, kale veya vezir', '2 kare', 'başka taşını', 'Arındırma'],
    ['bishop, rook or queen', '2 squares', 'another piece', 'Purify'],
  ),
  CardId.pawnDeviation: (
    ['boş hedefe', 'Son yataya', 'geçerken alma hakkı oluşturmaz', 'başka taş'],
    ['empty destination', 'final rank', 'no en passant right', 'another piece'],
  ),
  CardId.pawnAdvance: (
    [
      '2 kare',
      'önceden hareket etmiş',
      'geçerken alma hakkı doğar',
      'bu hakkı doğurmaz',
    ],
    [
      '2 squares',
      'after the pawn has moved',
      'en passant opportunity',
      'creates no such right',
    ],
  ),
  CardId.lockedSquare: (
    ['hâlâ boşsa', 'Şah', 'üzerinden', 'geçerken alma', 'sonunda biter'],
    ['while it is empty', 'Kings', 'pass through', 'en passant', 'expires'],
  ),
  CardId.freeze: (
    ['şah seçilemez', 'rok', 'başka bir taş', 'Arındırma'],
    ['non-king', 'Castling', 'another piece', 'Purify'],
  ),
  CardId.purify: (
    ['tek bir', 'tetiklenmiş Mayın', 'diğerleri kalır', 'tahta'],
    ['exactly one', 'triggered Mine', 'other overlapping', 'board'],
  ),
  CardId.mine: (
    [
      'bir aktif Mayın',
      'Tetikleyen hamledeki',
      'başka taşlar',
      'o taş hareket edince',
      'şahlar',
    ],
    [
      '1 active Mine',
      'triggering move',
      'other pieces',
      'when that piece moves',
      'kings',
    ],
  ),
  CardId.breakSeal: (
    [
      'Mayın, Kilitli Kare, Sis veya Tahta Mührü',
      'tüm alanıyla',
      'Tetiklenmiş Mayın',
      'yeminler',
    ],
    [
      'Mine, Locked Square, Fog or Board Seal',
      'whole effect',
      'triggered Mine',
      'vows',
    ],
  ),
  CardId.fog: (
    ['2 × 2', 'alanla bağlıdır', 'kart aşaması kapanınca', 'gizlemez', 'Mayın'],
    [
      '2 × 2',
      'zone, not the pieces',
      'card phase closes',
      'does not hide',
      'Mine',
    ],
  ),
  CardId.manaSabotage: (
    ['+1 mana', 'elinde olduğunu', 'kart aşaması kapanınca', 'en az 1'],
    [
      '+1 mana',
      'whether it is in their hand',
      'card phase closes',
      'minimum cost of 1',
    ],
  ),
  CardId.cardBlock: (
    ['sıradaki kart aşamasında', 'feda edebilir', 'silmez', 'taş hamlesini'],
    [
      'next card phase',
      'discard the blocked card',
      'does not delete',
      'chess move',
    ],
  ),
  CardId.rookBend: (
    ['1 kare', 'boş hedefe', 'rok hakkını kalıcı', 'geri dönmesi'],
    [
      '1 diagonal square',
      'empty destination',
      'permanently removes castling',
      'returning',
    ],
  ),
  CardId.angryN: (
    ['yatay veya dikey', 'rakip taşı', 'Av Yemini', 'Başka taş'],
    ['orthogonal', 'opposing non-king', 'Hunt Vow', 'No other piece'],
  ),
  CardId.shadowPass: (
    ['tam bir dost', 'ikinci taşın', 'şahın', 'boş kareye', 'rok hakkını'],
    [
      'exactly 1 friendly',
      'second piece',
      'any king',
      'empty square',
      'castling rights',
    ],
  ),
  CardId.huntVow: (
    [
      '2 kendi taş hamlen',
      'normal satranç yakalaması',
      '+2 mana',
      '6 sınırını',
      'ödül vermez',
      'yalnızca bir',
    ],
    [
      '2 own chess moves',
      'normal chess move',
      '+2 mana',
      'capped at 6',
      'no reward',
      'only 1 active',
    ],
  ),
  CardId.watchVow: (
    [
      'sıradaki taş hamlesi sonunda',
      'şah da sayılır',
      '+2 mana',
      'kazanılmasa da',
      'yalnızca bir',
    ],
    [
      'next chess move',
      'king counts',
      '+2 mana',
      'whether or not',
      'only 1 active',
    ],
  ),
  CardId.echo: (
    [
      'sıradaki kart aşamasında',
      '+2 mana',
      '6 sınırını',
      'feda etmek',
      'ödül vermez',
    ],
    ['next card phase', '+2 mana', 'capped', 'Discarding', 'no reward'],
  ),
  CardId.fateExchange: (
    [
      'feda et',
      'en fazla 3',
      'birini eline al',
      'sırasını seç',
      'normal',
      'gizli kalır',
    ],
    [
      'Sacrifice another',
      'up to 3',
      'take 1',
      'order the others',
      'not the normal',
      'stay private',
    ],
  ),
  CardId.shadowContract: (
    [
      'feda et',
      'Bir sonraki kendi',
      '2 azalır',
      'en az 1',
      'bu turda başlamaz',
      'mana kazandırmaz',
    ],
    [
      'Sacrifice another',
      'next own',
      'decrease by 2',
      'minimum cost of 1',
      'does not start this turn',
      'grant mana',
    ],
  ),
  CardId.boardSeal: (
    [
      'en az bir boş',
      'o anda boş',
      'Şah',
      'dolu karede',
      'geçerken alma',
      'sonunda biter',
    ],
    [
      'at least 1 empty',
      'currently empty',
      'Kings',
      'occupied square',
      'en passant',
      'expires',
    ],
  ),
};

AuthoritativeBattleState _ready(CardId card) {
  final deck =
      [card, ...CardId.values.where((id) => id != card)].take(10).toList();
  final state = DeckManager.newBattle(
    white: deck,
    board: Board.fromFen('4r2k/2b2p2/1n3q2/8/8/P7/4P3/RN1B3K w - - 0 1'),
  );
  final draft =
      RuleDraft(state.rules)
        ..phase = BattlePhase.card
        ..ownTurns = {_white: 2, _black: 2}
        ..mana = {_white: 6, _black: 6};
  if (card == CardId.purify) {
    draft.pieceEffects.add(
      ActivePieceEffect(
        id: 'negative',
        type: PieceEffectType.chain,
        owner: _black,
        pieceId: draft.pieceIds[0]!,
        responseSide: _white,
        duration: EffectDuration.move,
      ),
    );
  }
  if (card == CardId.breakSeal) {
    draft.boardEffects.add(
      BoardEffectInstance(
        id: 'opposing-mine',
        type: BoardEffectType.mine,
        owner: _black,
        squares: [26],
        responseSide: _white,
        duration: EffectDuration.persistent,
      ),
    );
  }
  return AuthoritativeBattleState(draft.freeze(), state.hidden);
}

void main() {
  test('copy covers exactly the 24 canonical cards', () {
    expect(CardId.values, hasLength(24));
    expect(_criticalCopy.keys.toSet(), CardId.values.toSet());
    for (final language in ['tr', 'en']) {
      final l = LunoLocalizations(Locale(language));
      expect(CardId.values.map(l.battleCardName).toSet(), hasLength(24));
    }
  });

  for (final language in ['tr', 'en']) {
    for (final card in CardId.values) {
      test(
        '${card.wire} $language has concise copy and complete canonical details',
        () {
          final l = LunoLocalizations(Locale(language));
          final short = l.battleCardDescription(card);
          final detail = l.battleCardDetail(card);
          expect(short, isNotEmpty);
          expect(short.length, lessThanOrEqualTo(180));
          expect(short, isNot(contains('\n')));
          expect(detail.length, greaterThan(short.length));
          expect(detail, contains('${cardDefinitions[card]!.cost} mana.'));
          for (final token
              in language == 'tr'
                  ? _criticalCopy[card]!.$1
                  : _criticalCopy[card]!.$2) {
            expect(
              detail,
              contains(token),
              reason: '${card.wire} $language: $token',
            );
          }
          expect(detail, isNot(contains('/29')));
          expect(detail, isNot(contains('6-slot')));
          expect(detail, isNot(contains('stateVersion')));
        },
      );
    }

    test('$language uses public cards, hidden Deck, Hand and explicit 5+2', () {
      final l = LunoLocalizations(Locale(language));
      expect(
        l.battle(BattleCopy.arsenal),
        language == 'tr' ? 'Rakibin Kartları' : 'Opponent Cards',
      );
      expect(l.battle(BattleCopy.deck), language == 'tr' ? 'Deste' : 'Deck');
      expect(l.battle(BattleCopy.hand), language == 'tr' ? 'El' : 'Hand');
      expect(l.battle(BattleCopy.chooseCard), isNot(contains('deck')));
      expect(l.battle(BattleCopy.chooseCard), isNot(contains('deste')));
      expect(l.battleTimeControl, '5+2');
      expect(l.battleTimeControlDescription, contains('5'));
      expect(l.battleTimeControlDescription, contains('+2'));
    });

    test(
      '$language learning copy keeps Academy optional and the chess move after discard',
      () {
        final l = LunoLocalizations(Locale(language));
        expect(l.battleLessons, hasLength(10));
        final phaseHint = l.battleLessons[2].hint;
        expect(
          phaseHint,
          contains(
            language == 'tr'
                ? 'feda etmek hamle hakkını tüketmez'
                : 'discarding does not consume that move',
          ),
        );
        final finalHint = l.battleLessons.last.hint;
        expect(
          finalHint,
          contains(language == 'tr' ? 'isteğe bağlıdır' : 'optional'),
        );
        expect(finalHint, isNot(contains('dört kısa')));
        expect(finalHint, isNot(contains('four short')));
        final text = l.battleLessons
            .map((s) => '${s.title} ${s.body} ${s.hint}')
            .join(' ');
        expect(text, contains('10'));
        expect(text, contains('3'));
        expect(text, contains('4'));
        expect(text, contains('5+2'));
        expect(text, isNot(contains("Opponent's Deck")));
        expect(text, isNot(contains('Rakibin Destesi')));
      },
    );
  }

  for (final card in CardId.values) {
    test(
      '${card.wire} documented cost and target agree with a real accepted cast',
      () {
        final before = _ready(card);
        final target =
            BattleRulesCore.cardTargets(before.view(_white), card).first;
        final cast = BattleRulesCore.legalActions(
          before.view(_white),
        ).whereType<PlayCardAction>().firstWhere(
          (action) => action.card == card && action.target == target,
        );
        final after = DeckManager.apply(before, cast);
        expect(after.rules.used[_white], contains(card));
        expect(after.rules.mana[_white], 6 - cardDefinitions[card]!.cost);
        expect(after.hidden.hands[_white], isNot(contains(card)));
        if (movementCards.contains(card)) {
          expect(after.rules.special?.card, card);
          expect(after.rules.phase, BattlePhase.chess);
        }
        if (card == CardId.prophecy || card == CardId.fateExchange) {
          expect(after.rules.phase, BattlePhase.pending);
          expect(
            after.view(_white).knowledge.pendingCards,
            hasLength(card == CardId.prophecy ? 2 : 3),
          );
          expect(after.view(_black).knowledge.pendingCards, isEmpty);
          final resolve =
              BattleRulesCore.legalActions(
                after.view(_white),
              ).whereType<ResolveAction>().first;
          final resolved = DeckManager.apply(after, resolve);
          expect(resolved.rules.phase, BattlePhase.chess);
          expect(
            resolved.rules.deckCounts[_white],
            before.rules.deckCounts[_white]! -
                (card == CardId.fateExchange ? 1 : 0),
          );
          expect(
            resolved.rules.drawCounts[_white],
            before.rules.drawCounts[_white]! +
                (card == CardId.fateExchange ? 1 : 0),
          );
        }
        if ([
          CardId.shelter,
          CardId.chain,
          CardId.slow,
          CardId.freeze,
        ].contains(card)) {
          expect(
            after.rules.pieceEffects.single.duration,
            card == CardId.shelter ? EffectDuration.card : EffectDuration.move,
          );
        }
        if ([
          CardId.mine,
          CardId.lockedSquare,
          CardId.fog,
          CardId.boardSeal,
        ].contains(card)) {
          expect(after.rules.boardEffects.single.duration, switch (card) {
            CardId.mine => EffectDuration.persistent,
            CardId.fog => EffectDuration.card,
            _ => EffectDuration.move,
          });
        }
        if (card == CardId.huntVow || card == CardId.watchVow) {
          expect(
            after.rules.vows.single.remainingMoves,
            card == CardId.huntVow ? 2 : 1,
          );
        }
        if ([
          CardId.manaSabotage,
          CardId.cardBlock,
          CardId.echo,
          CardId.shadowContract,
        ].contains(card)) {
          final modifier = after.rules.modifiers.single;
          expect(modifier.ownTurn, 3);
          expect(
            modifier.responseSide,
            card == CardId.shadowContract ? _white : _black,
          );
        }
      },
    );
  }

  test('5+2 clock gives increment only after a completed chess move', () {
    var time = 0;
    final clock = BattleV1LocalClock(now: () => time);
    expect(clock.remaining(_white), 300000);
    time = 500;
    clock.advance(_white, chessMove: false);
    expect(clock.remaining(_white), 299500);
    time = 1000;
    clock.advance(_black, chessMove: true);
    expect(clock.remaining(_white), 301000);
  });
}
