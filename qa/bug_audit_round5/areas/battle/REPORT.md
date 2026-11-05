# Round 5 battle/tutorial audit

Baseline: `6467e72f6181efc10420a98df1b7d7977cdf757a`. Production source was not edited or swapped during baseline investigation. After the failing proof and external proposal were reviewed, the parent authorized applying the exact patch; actual-production verification follows below. No commits, golden updates, screenshots, builds, emulators, live services or deployments were used.

## Confirmed P2: private choice callbacks do not preserve the painted choice

Conservative count: **one residual scope defect in the prior stale-input/selection family**, not four new bugs. Public Play/Discard/Pass gates from rounds 3 and 4 protect `BattleInteraction`; the private Fate Exchange/Prophecy reorder sheet has a separate local selection model and was not covered.

Source: `luno_chess/lib/battle_ui/private.dart` lines 32, 77–88, 125–133, 148–165.

The private sheet captures row indices, then dereferences mutable `order` at callback invocation. In Fate Exchange, with Radar/Prophecy/Chain painted, moving Radar down and taking the still-painted Radar row before the next frame takes Prophecy. Invoking Radar's painted down button twice moves Prophecy on the second invocation. These are ordinary UI callback sequences; tests do not directly mutate the widget state or authority.

Confirm has the same missing input-generation boundary: its callback reads `choice` at invocation rather than checking the painted ResolveAction. After a reorder before the next frame, the old Confirm closes the actual modal and returns the newly computed, never-painted deck order. Both Fate Exchange and Prophecy reproduce this. The authority considers the action legal, so server rule validation cannot recover the user's intended order.

The regression mounts a real modal from a legal authoritative pending state, invokes UI callbacks without an intervening frame, then checks selected CardId/order and modal survival. Freshly painted take/confirm controls remain usable. Source test: `luno_chess/test/round5_battle_private_choice_test.dart`.

## Minimal proposal

`private-choice-proposed.patch` is the preserved reviewed unified diff; it was applied only after valid baseline proof and explicit parent authorization. It binds row callbacks to CardId, resolves that CardId's current reorder index, captures the painted ResolveAction, and rejects Confirm when its action key no longer matches the current choice. Card rules, assets, atlas, ownership and stateVersion gates remain unchanged.

`private_choice_candidate.dart` is the same proposed widget with package imports for isolated testing. The temporary `round5_battle_private_choice_patch_test.dart` substitutes only that external widget import, preserving the regression assertions. Passing this copy is proposal evidence, not a claim that production source has been fixed.

## Verification

Initial sandbox run failed to create its normal localhost test socket and ran zero cases; preserved in `private-choice-baseline.log`. Approved normal IPC runs follow and are separate evidence.

First bounded baseline: 1 passed / 2 failed. Expanded baseline: 1 passed / 3 failed; external proposed widget: 4/4 passed. These earlier overlapping runs are not added to final totals.

Final run: **37 passed / 4 failed / 0 skipped**, 41 cases across 5 files; the four failures are the newly demonstrated production-source defect. Breakdown:

- Current-source private choice: **3 passed / 4 failed**, 7 cases.
- External proposed widget: **7/7 passed**; assertions identical except widget import.
- Existing V232 motion boundaries: **14/14 passed**.
- Existing V238 emote picker ownership/reopen boundaries: **5/5 passed**.
- Existing welcome/tutorial lifecycle: **8/8 passed**.

The 27 existing boundary cases passed on the unchanged source. The group as a whole remains FAIL; external-copy passes do not make production source green. Log: `final-baseline-proposal-boundaries.log`. Every Flutter/Dart command used the handoff toolchain and the shared `flock`, concurrency 1.

The temporary external-import candidate test was moved out of the game repository after execution to `round5_battle_private_choice_patch_test.dart.as-run`; restore its original `luno_chess/test/` location to reproduce its exact import resolution. The main current-source regression remains in the repository.

## Scope and limits

Reviewed BattleV1Screen lifecycle, local visibility and restart, private sheets and owner/version admission, emote picker reopen/cover handling, target/card/draw/cast feedback reset and accepted-frame retention, audio cancellation, practice campaign completion and tutorial callbacks. Existing boundary tests exercise route cover/resume, owner changes, canceled delayed audio, skipped history, invalid origins and reduced motion.

No additional independent battle/tutorial source defect was confirmed. Screen controller replacement has no `didUpdateWidget`, but actual production entry routes construct fresh BattleV1Screen instances and the campaign keys screens by account/stage; an injected-controller replacement alone is not counted as a production bug. Historical 97 golden mismatches and the native crash remain open and were neither retested nor reclassified.

## Authorized actual-production fix and verification

The exact reviewed patch is now applied to `luno_chess/lib/battle_ui/private.dart`: **16 insertions / 14 deletions**. `actual-production.patch` records the resulting Git diff. The owned 7-case regression remains `luno_chess/test/round5_battle_private_choice_test.dart`; the temporary external-import harness remains archived outside the repository. No other source edits were made by this worker and nothing was committed.

Actual production test command (handoff environment, shared flock, concurrency 1):

```sh
flutter test --no-pub --concurrency=1 test/round5_battle_private_choice_test.dart test/v232_battle_motion_boundaries_test.dart test/v238_emote_picker_owner_test.dart test/tutorial_live_safety_test.dart --reporter expanded
```

**34 passed / 0 failed / 0 skipped**, 4 files: new private-choice **7/7**, existing V232 motion **14/14**, V238 emote ownership **5/5**, tutorial/welcome **8/8**. This run imports the actual modified production widget; no external-copy result is substituted. Log: `actual-production-fixed.log`. `git diff --check` passed and the applied widget bytes equal `private.dart.proposed` exactly.

Affected-file SHA-256:

- `private.dart`: `15c7962aa04a2c717ccd9237de41f3988a4877506aa2c6d8720b106894af692a`
- `round5_battle_private_choice_test.dart`: `a38fd80a94b02fac3377f30f2b62cf8554d9a4ce05fa1b931a2fd275ee4f81aa`

Baseline **3 pass / 4 fail** becomes actual production **7/7 pass** without changing assertions. This closes the one P2 residual private-choice stale-input defect in the bounded verified scope. No full suite, build, emulator or golden update was performed.
