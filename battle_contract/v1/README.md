# Luno Battle Rules V1

This directory is the versioned V201-A test contract. It does not activate the
new rules in production. UI, online protocols, secure shuffle, storage separation
and legacy match migration are V201-B work.

## Implementations

- Native: `luno_chess/lib/battle_v1/{model,core,authoritative}.dart`.
- Independent TypeScript: `functions/rules-v1/src`.
- Both consume explicit ten-card deck orders; neither shuffles in cross-language
  tests. Dart uses the existing immutable Board/MoveGen. TypeScript uses the
  pinned chess.js orthodox generator and independent card/geometry rules.
- Public RuleState has counts and sorted public arsenals, never deck order or
  opponent hand identities. PlayerView adds only the viewer's own hand and
  legitimate private knowledge. Secret resolution belongs to DeckManager.
- Rules return immutable snapshots. Invalid actions are validated before copying
  and cannot mutate their input. Pending reveals are bounded before permutations.

## References And Expectations

- `cards.json`: manually authored 24-card metadata and canonical starter deck.
- `perft.json`: independently checked against
  [CPW Perft Results](https://www.chessprogramming.org/Perft_Results).
- `rules.json`: manually authored legality/state expectations. Engine output is
  never accepted as expected truth. `expect` paths select exact values, including
  authoritative hidden values only in authoritative runners. `contains` and
  `excludes` are partial diagnostic checks, not substitutes for the complete-set
  differential comparison. `branch` names identify mandatory rejection coverage.

## Running

From `luno_chess`, use the project's configured Dart/Flutter SDK:

```powershell
flutter test --no-pub test/battle_v1
dart run tool/luno1_perft.dart
dart compile exe tool/battle_json_runner.dart -o qa/v201a-battle-runner.exe
```

From `functions/rules-v1`:

```powershell
npm ci
npm run test:chess
npm run test:core
npm run test:fixtures
npm run test:differential
npm run typecheck
```

`LUNO_SLOW_PERFT=1` enables preserved deeper counts in the existing Flutter perft
tests; `dart run tool/luno1_perft.dart --slow` runs the additional shared depths.
Mandatory normal regression uses the specified 20 fast reference checks.

Differential failures save the scenario ID, seed, initial setup, explicit decks
and exact action sequence in `qa/v201a-differential-failure.json`. That file is
diagnostic evidence, not a golden. A later successful run does not erase history.

## Repetition Invariant

Occurrences are recorded at stabilized turn boundaries, never during a secret
choice. Public fingerprints include mana, phase/first-turn state, piece identity,
rights, legally available EP, counts, public used/discarded cards and effects.
Relative modifier timing is included; halfmove/fullmove, absolute turn counters,
effect sequence and private knowledge are not.

Within a match, hidden hands/decks can change only through: public PLAY/DISCARD
sets growing, draw counters increasing, or a one-use secret card being played
and resolved. Thus a hidden draw/reorder change cannot return to the same public
fingerprint without a monotone public field changing. Tests check this property
on repeated chess boundaries and separately demonstrate fivefold after all ten
cards are exhausted. Across distinct matches, identical public fingerprints may
legitimately correspond to different initial secret shuffles; occurrences are
always match-local.

Pure chess still exposes the existing 50/threefold claims and 75/fivefold
primitives. The new battle core enforces automatic 75/fivefold, with checkmate
precedence. Its public repetition is Luno-specific, not board-only repetition.
