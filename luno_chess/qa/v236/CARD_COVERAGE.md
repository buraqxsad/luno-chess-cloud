# V236 Card Coverage: Reconciled Evidence

Reconciled on 2026-10-26 from existing V236 source, JSON and logs. This sidecar
did not run Flutter, Dart, Node tests, a server, an emulator or a live service.
The retained execution artifacts were last written on 2026-10-22; this is fresh
evidence reconciliation, not a claim of a new test execution today.

Root: `C:\Users\Casper\Documents\Luno Chess\luno-chess-src\luno_chess`.
Only Battle V1 is described here, not the legacy card/upgrade engine.

## Catalog And Duration Contract

[card-catalog.json](card-catalog.json) contains **24 entries / 24 unique IDs**.
[export-cards.dart](export-cards.dart) exports the current Dart definitions and
presentation timings separately. IDs, costs, rarity, category and target fields
match the inspected [Dart model](../../lib/battle_v1/model.dart) and
[TypeScript model](../../../functions/rules-v1/src/model.ts). No card price,
power or rule was changed by this sidecar.

Rule lifetimes below come from [Dart core](../../lib/battle_v1/core.dart) and
[TypeScript core](../../../functions/rules-v1/src/core.ts), not from milliseconds:

- `C`: expires when the opposing response card window closes, including pass or discard.
- `M`: expires after the opposing response chess move, not only when the targeted piece moves.
- `S`: authorizes the current chess move only; it is not an extra move.
- `N`: targets the opponent's next card window; consumed/expired when that window closes.
- `O`: discount for the caster's next card window; unused discount also expires on pass/discard.
- `P`: persistent mine until a qualifying enemy non-king arrival or explicit removal; its resulting no-capture debuff lasts until that affected piece's next move or removal.

The visual columns are **total presentation / impact delay in milliseconds**,
from [effect_timing.dart](../../lib/battle_ui/effect_timing.dart). They are not
effect TTLs, measured device animation timings, clock pauses or delayed rules
acceptance. `casts` is the corresponding `counts["card:<id>"]` event count in
the fresh V236 differential JSON, not a unique-test count or a coverage score.

| Card ID | Mana | JSON target | Rule result / lifetime | Visual total / impact ms | Differential casts |
| --- | ---: | --- | --- | ---: | ---: |
| `radar` | 1 | `opponent_card` | Instant in-hand query; retained observation is not continued surveillance | 1600 / 480 | 103 |
| `prophecy` | 1 | `none` | Inspect/reorder up to two deck cards; pending until valid resolution | 1800 / 540 | 60 |
| `shelter` | 2 | `own_piece` | Direct hostile card-target protection, C | 1600 / 480 | 39 |
| `chain` | 2 | `opponent_piece` | Target cannot capture, M | 1700 / 510 | 47 |
| `slow` | 2 | `opponent_slider` | Bishop/rook/queen range at most two squares, M | 1800 / 540 | 44 |
| `pawn_deviation` | 2 | `own_pawn` | One empty forward-diagonal pawn move, S | 1500 / 450 | 62 |
| `pawn_advance` | 2 | `own_pawn` | Two-square forward pawn authorization with intermediate/destination checks and canonical en-passant distinction, S | 1400 / 420 | 69 |
| `locked_square` | 2 | `empty_square` | Blocks opposing empty-square landing, not an otherwise legal capture, M | 1600 / 480 | 48 |
| `freeze` | 4 | `opponent_piece` | Target cannot move, M | 1900 / 570 | 69 |
| `purify` | 1 | `own_piece_effect` | Immediately remove one eligible negative effect by unique effect ID | 1700 / 510 | 47 |
| `mine` | 2 | `empty_square` | Public trap, one active mine per owner; P | 1800 / 540 | 48 |
| `break_seal` | 1 | `opponent_board_effect` | Immediately remove one selected opposing board-effect instance | 1700 / 510 | 52 |
| `fog` | 3 | `zone` | Direct hostile card-target protection in a valid 2x2 zone, C | 2000 / 600 | 39 |
| `mana_sabotage` | 2 | `opponent_card` | Selected card costs +1 in N | 1800 / 540 | 37 |
| `card_block` | 3 | `opponent_card` | Selected card cannot be played in N; discard is distinct | 1700 / 510 | 29 |
| `rook_bend` | 2 | `own_rook` | One diagonal rook step, S | 1800 / 540 | 50 |
| `angry_n` | 3 | `own_knight` | One orthogonal knight step, S | 1800 / 540 | 70 |
| `shadow_pass` | 3 | `own_bishop_rook` | Bishop/rook crosses exactly one friendly blocker on an authorized line, S | 2000 / 600 | 50 |
| `hunt_vow` | 2 | `opponent_piece` | +2 mana for normal capture of the vowed piece within two caster moves; special-move capture does not earn it | 1900 / 570 | 88 |
| `watch_vow` | 2 | `empty_square` | After the next opposing move, opposing occupancy of the predicted square earns +2 mana; then resolves | 1900 / 570 | 68 |
| `echo` | 2 | `opponent_card` | Opponent playing the named card in N earns caster +2 mana | 2100 / 630 | 40 |
| `fate_exchange` | 3 | `sacrifice` | Sacrifice another held card, inspect up to three, select one and reorder remainder; pending until resolution | 2200 / 660 | 45 |
| `shadow_contract` | 1 | `sacrifice` | Sacrifice another held card for -2 next-window cost, minimum effective cost 1, O | 2100 / 630 | 47 |
| `board_seal` | 5 | `zone` | Valid 2x2 zone with at least one empty square; opposing empty-square landing restricted, M | 2200 / 660 | 53 |

Own/enemy piece targets exclude kings where required by the canonical target
validator. Piece effects track piece identity; removal targets an effect ID,
not every effect on a square. Siper/Fog do not make normal captures illegal.
All mana gains remain capped at 6. Pending knowledge is viewer-private.

The canonical engine checks mate/stalemate after a chess move before opening
the next card window. A theoretical Purify/Break Seal rescue does not override
that terminal boundary. This is retained rule behavior, not a newly diagnosed
defect or an unapproved rule change.

## Executed Coverage And Its Limits

| Evidence | Actual observed scope | Interpretation |
| --- | --- | --- |
| [V236 broad log](flutter-regression.txt), [117-file manifest](flutter-test-files.txt) | 4989 pass / 51 fail overall | Card portions passed, but the complete broad run was not green; reconciliation is in [TEST_REPORT.md](TEST_REPORT.md). |
| [Card stress source](../../test/battle_v1/card_stress_v212_test.dart), same V236 log | 24 named tests, each iterating 1000 deterministic variants; both side orientations, mana/phase/modifier variations, authority, inventory, discard and chess continuation | 24000 loop variants inside 24 test cases, not 24000 additional test-runner passes. The `v212` filename is not an old run reused as fresh evidence. |
| [All-square interaction source](../../test/v223_all_square_interaction_test.dart), same V236 log | Each of 24 cards, both colors, all 64 square taps in the authored fixtures | 48 named tests containing tap loops; not every possible board position or flipped-device layout. |
| [TS rules log](typescript-rules-tests.txt) | 373 pass / 0 fail / 3 skip | Compiled rules/fixture/authority tests; skipped targeted Dart/TS tests remain skipped. |
| [Differential JSON](differential/v201a-differential-summary.json), [run log](differential-run.txt), [generator](../../../functions/rules-v1/test/differential.ts) | 3101 scenarios; 10967 states and 10967 legal-action sets; 0 legal-set and 0 resulting-state divergences; 12 repetition and 3820 redaction checks | Current V236 output despite the historical `v201a` basename. It compares two engines, not two real online clients. |

The differential generator includes fixed contract fixtures, 24 seeds in each
of natural/card-biased families, deterministic edge variants and explicit
negative branches. Read-only JSON reconciliation found all **56 positive
coverage minima and 188 rejection minima** satisfied. Every card has at least
20 recorded casts and five probes per generic rejection branch (mana, phase,
first turn, invalid target, not held). These are bounded registries, not a
complete Cartesian product of card interactions.

Actual combination evidence includes:

- [Shared fixtures](../../../battle_contract/v1/rules.json) and [Dart fixture tests](../../test/battle_v1/fixtures_test.dart): `mine-capture-overlap`, `fog-mine-overlap`, `break-one-overlap`; present in both V236 Dart and TS logs.
- [Dart core tests](../../test/battle_v1/core_test.dart) and [TS core tests](../../../functions/rules-v1/test/core.test.ts): one-instance removal with overlaps, protection checks, next-turn discount plus sabotage and pass/discard expiry.
- [Freeze adversarial tests](../../test/v223_freeze_adversarial_test.dart): Purify selects one overlapping Freeze/Mine effect for both colors.
- [Locked-square adversarial tests](../../test/v223_locked_square_adversarial_test.dart) and [Mine adversarial tests](../../test/v223_mine_adversarial_test.dart): rejected landing does not consume an overlapping mine; Break Seal removes only its selected instance.
- [Pawn-advance adversarial tests](../../test/v223_pawn_advance_adversarial_test.dart) and [branch helpers](../../test/helpers): restriction combinations, special movement, lost replies, timeout and terminal recovery in authored fixtures.
- Differential counters include 65 overlaps, 21 break-overlap observations, 21 mine/watch observations, 24 castlings, 20 en-passant events and 20 promotions. Counters overlap and are not summed.

Tests merely present in the checkout are not automatically executed evidence.
For example, `v222_all_card_contract_test.dart` and
`v226_card_effect_semantics_test.dart` are not in the retained 117-file manifest;
this report does not claim a fresh V236 execution of those files.

## Presentation And Remaining Acceptance

[Final affected Flutter run](flutter-affected-final.txt) ended **250 pass / 0
fail** and includes visual, battle readability, tutorial, learning, hotseat,
account and font suites. [Golden regeneration](golden-regeneration.txt) ended
50/0 with update mode; 46 changed reference states have
[preserved hashes/contact sheets](golden-review/manifest.json). Regeneration
itself is not visual acceptance. No new pixel inspection or sound listening
was performed by this sidecar.

Automated rules/stress/differential evidence: **PASS within the stated scope**.
All possible card pairs, longer combinations, positions, deck orders, network
schedules and lifecycle interleavings: **not exhaustively tested**. Human
balance, actual Android VFX/audio synchronization, reduced-motion experience,
TalkBack, long-session performance and two-device live play: **NOT RUN here**.
No human win-rate, readiness score or zero-defect guarantee is inferred.
Overall Android release decision remains **RELEASE HOLD**.
