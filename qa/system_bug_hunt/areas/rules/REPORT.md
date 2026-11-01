# Rules/engine bug hunt

**No new confirmed production bug found.** No production file, contract fixture, existing test, assertion or golden was changed. The owned source paths remain byte-identical to baseline `fc11b702876d0d5c181c545bf6e52319fdddc520`; hashes are in `source-provenance.json`. Other agents made unrelated worktree edits while this focused review ran. These results are not a final whole-product release acceptance.

Reviewed: legal action validation; five movement cards and normal/quiet EP semantics; castle rook restrictions and piece identity; promotion/capture; card-window effect expiry; mine entry/debuff; shelter/fog protection; draw counters and 75-move/checkmate precedence; Luno-specific public repetition; private card/knowledge projection and deterministic bot input. Public Mines and repetition history are explicitly intended by the current contract, so their presence was not misreported as a secret leak. Bare-kings battle continuation is also explicitly tested by the contract, unlike pure orthodox chess's dead-position draw.

| Current focused check | Result |
| --- | --- |
| Flutter engine, local clock, terminal, repetition, mine, remaining card semantics and Pawn Advance adversarial | 488 pass / 0 fail / 0 skip |
| Direct-node six TS files | 148 pass / 0 fail / 1 opt-in Dart bridge skip (149 registered) |
| Independent conservation/identity/knowledge probe | 48 deterministic games, 8654 inspected states, 4331 chess moves, 8606 atomic illegal rejections; all 24 cards cast; PASS |
| Dedicated retained-input immutability probe | 8 deterministic games, 1448 states / 1440 transitions; PASS |

The custom probes state independent invariants: ten unique deck cards remain partitioned across hand/deck/used/discarded; hand/deck counters agree; every occupied square has a unique identity and exactly one king per color; mana stays in range; known/pending cards match actual deck prefixes; nonstale Radar observations remain accurate; illegal actions leave their inputs intact. Conservation run is not used as accepted-action immutability evidence; the dedicated probe explicitly retains and checks the original input object after accepted actions. Neither probe is an independent complete rules oracle or a fresh Dart/TS differential. Overlapping states/test counts are not summed.

Focused Flutter command (under shared `flutter.lock`, pinned `luno-env.sh`):

```sh
flutter test --no-pub --concurrency=1 test/engine test/battle_v1/local_clock_test.dart test/v218_rules_terminal_test.dart test/v219_rules_repetition_contract_test.dart test/v219_rules_mine_contract_test.dart test/v223_remaining_card_semantics_test.dart test/v223_pawn_advance_adversarial_test.dart
```

TypeScript build used pinned `npm --prefix functions/rules-v1 run build`. Each compiled file was then executed directly with `node functions/rules-v1/dist/test/<name>.test.js`: `chess`, `v218-rule-geometry`, `v219-rules-contract`, `v223-removal-identity`, `v223-terminal-cards`, `v224-card-wire-targets`. Direct log names and per-file counts are in `typescript-direct-results.json`. The one skipped cross-language case requires `LUNO_DART_RUNNER`; root owns the final fresh differential run.

Two reviewer/runner attempts are preserved and excluded: first Flutter invocation named a nonexistent test path (41 actual passes plus one load error), corrected to the real files above; initial `node --test` gave only six file-level outer outcomes, replaced by direct per-case execution. No test assertion was relaxed to make either pass. No new untracked QA output was produced by the valid Flutter run.

No emulator, physical device, production/staging Firebase, payment, deployment, signing, upload or publication was performed. Existing native crash/performance/real Play/Firebase release gates remain outside this agent's acceptance. See `results.json` and raw logs for exact evidence.
