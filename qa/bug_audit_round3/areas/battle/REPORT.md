# Battle selection command audit, round 3

**One NEW P2 source defect reproduced and fixed.** A Play, Discard or Pass command retained from the painted frame could submit a previous decision after the interaction model had already changed. The action still passed the unchanged rules' legality checks, so those checks did not detect that the player had selected another square/card. A retained cast could also fire after reconnect advanced to a later turn in which the same card and target were legal again.

Baseline: `d627e06a963e6ab5f85d479ac53cbb161eb8ce3f`, branch `codex/cloud-transfer-20261027`. Only `luno_chess/lib/screens/battle_v1_screen.dart` and new `luno_chess/test/round3_battle_selection_test.dart` were changed by this agent. Other agents' working-tree changes were left alone.

## Reproduction and controls

The real BattleV1Screen, interaction model and controller are mounted with the existing fixture transport and real Dart rules. Invoking the real widget callbacks before pumping the next frame represents two queued input events; no production bypass is introduced.

- Select Shelter and target e2. Before rebuilding, target d2 and invoke the previous Play callback. Baseline dispatches the old e2 cast.
- Select Shelter, retain Discard, select Chain before rebuilding and invoke Discard. Baseline discards Shelter.
- Retain Pass, select Shelter before rebuilding, then invoke Pass. Baseline skips the card phase despite the new selection.
- Retain a Shelter d2 command. Advance the authority through three independently admitted legal actions, Pass → e2e4 → e7e5, and reconnect. The interaction selection clears on the new version, but the old callback still casts Shelter on d2. This uses real legal transitions, not a version-only artificial update.

The three original controls rebuild after the new selection, then confirm the new target, discard the new card, or explicitly pass after cancellation. Each passed before the fix. `rawlogs/selection-before-legal.log`: **3 pass / 4 fail**, exit 1. All four failures are unintended action dispatch; they are one root-cause family. The earlier `selection-before.log` also records 3/4, but its last case used a version-only update; the stronger legal-transition run is the final baseline evidence. `selection-sandbox-blocked.log` is an initial loopback socket infrastructure failure and is not a product repro.

## Fix and review

The existing four selection controls (Play, Discard, Pass and Cancel) now capture the current version, selected card, play key, bound movement destination and hotseat privacy epoch. Their admission wrapper rejects commands when those values no longer match; current readiness, route/account/lifecycle and rules checks still apply. No engine, game-rule, balance, action protocol, timer, audio, artwork or atlas code changed.

The guard compares meaningful values, not widget identity. An added control retains Play across a same-version reconnect/rebuild with an unchanged selection, and successfully submits that original command. Review also checked duplicate press rejection via sending/readiness, movement destination binding, invalid target clearing, hotseat conceal/epoch, disposal/account/route guards and terminal readiness. This is scoped source review, not evidence that every possible sequence is fault-free.

## Verification

Pinned luno-env, one shared Flutter flock, `--no-pub --concurrency=1`:

```text
flutter test --no-pub --concurrency=1 --reporter=expanded \
  test/round3_battle_selection_test.dart \
  test/battle_ui/interaction_test.dart \
  test/v236_hotseat_screen_test.dart \
  test/rc_battle_modal_ownership_test.dart \
  test/tutorial_luno_live_test.dart
```

**66 pass / 0 fail**, exit 0, five files. The eight new tests are included in 66, not added again. Existing interaction (12), hotseat (12), modal ownership (8) and live tutorial (26) tests passed. Raw log: `rawlogs/selection-after-related.log`. `git diff --check` passed for the owned production file. No new untracked QA files were generated. No golden or tracked fixture changed.

These are bounded Flutter widget/controller/rules checks with fixture transport. No full suite, analyzer, native build/emulator, production Firebase/App Check/Google/Play, physical audio/GPU/FPS, deployment, payment, upload, signing change or push was performed. Existing release holds and historical golden/device/service issues remain outside this scoped result.
