# V236 Test Evidence Closure

Reconciled on **2026-10-26** from the attached acceptance request, current
`qa/v236` logs/handoffs, selected source and JSON. Retained execution artifacts
were last written on **2026-10-22**. This sidecar ran no Flutter/Dart SDK, test
runner, build, server, emulator, live request, purchase or deployment. Fresh
reconciliation is not a claim that those suites were rerun today.

Root: `C:\Users\Casper\Documents\Luno Chess\luno-chess-src\luno_chess`;
backend sibling: `..\functions`. Logs use the original `L:/luno-chess-src/...`
paths. Only `CARD_COVERAGE.md`, `ECONOMY_REPORT.md` and this file are sidecar-owned.
Final source/artifact identity, Android package acceptance and online reports
remain main-owned.

## Result Ledger: No Combined Total

| Retained evidence | Pass | Fail | Skip | What the result establishes |
| --- | ---: | ---: | ---: | --- |
| [First broad Flutter run](flutter-regression.txt), [117 unique files](flutter-test-files.txt) | 4989 | 51 | No skip counter reported | Broad selected regression, not all checkout tests and not a green final run |
| [Learning reconciliation](learning-reconciled.txt) | 89 | 0 | No skip counter reported | Four affected learning/tutorial/recovery files after reconciliation |
| [Golden regeneration](golden-regeneration.txt) | 50 | 0 | No skip counter reported | Update-goldens mode; reference generation, not independent visual approval |
| [Final affected Flutter run](flutter-affected-final.txt) | 250 | 0 | No skip counter reported | Nine affected files, including all 51 broad-run failure categories |
| [Menu captures](menu-captures.txt) | 62 | 0 | No skip counter reported | Deterministic Flutter screen-capture tests; actual tail is `01:29 +62: All tests passed!` |
| [Backend regression](backend-regression.txt) | 1267 | 0 | 1 | TAP total 1268; local backend tests, isolated RTDB integration skipped |
| [Current TS rules](typescript-rules-tests.txt) | 373 | 0 | 3 | TAP total 376; compiled rules tests, not an older summary count |

These runs overlap. In particular, the 89-test learning package is contained
in the nine-file affected rerun; the 50 regenerated visual states are tested
again within the affected run; backend focused checks are included in its full
suite. Scenario loops and differential counters are not test-runner cases.
**No grand total of unique passing tests is asserted.** A failed file-load
outcome is also not equivalent to one fully executed test file.

The broad log really ends `18:00 +4989 -51: Some tests failed.` It has not been
rewritten as a hypothetical all-green 117-file result. There is **no retained
second complete 117-file green run** after the final fixes. Closure consists
of the original passing coverage plus explicitly scoped later reruns, with the
remaining final-revision verification boundary stated below.

## Reconciliation Of The 51 Broad Failures

| Runner failures | Cause | Subsequent evidence / disposition |
| ---: | --- | --- |
| 46 | `battle_ui/visual_test.dart` reference mismatches after intentional portrait board/layout changes | Before references retained; 46 changed states in [goldens-changed.json](goldens-changed.json), [review manifest](golden-review/manifest.json) and contact sheets. 50 visual-state cases regenerated, then visual suite passed without update mode in the 250/0 run. |
| 1 | `online_deleted_session_recovery_test.dart` could not compile: fake `PausedErasureStore.bindAccount` lacked new optional `restoreExisting` named argument | Test fake brought into API parity. Recovery file executes in both 89/0 and 250/0 runs; not a product defect or permission to remove recovery assertions. |
| 4 | TR/EN live-card teaching (2) and TR/EN resumed-basics completion at 390x844, text scale 1.8 (2) could not find `lesson-speech-scroll` after layout changes | Restore the learning scroll/key contract and readable/reachable coach layout in [layout.dart](../../lib/battle_ui/layout.dart). These were learning-key/UX regressions, not golden differences. Both original learning suites plus tutorial/recovery tests passed 89/0, then again within 250/0. |

This accounts for all **46 + 1 + 4 = 51 runner failures**; it is not 51 root
product bugs. [FINDINGS.md](FINDINGS.md) is main's root-defect accounting and
must not be replaced by a count of failed assertions or improvement packages.
The sidecar itself made no product fixes.

Four terminal-scene golden states did not fail in the broad log. Old leftover
failure PNGs do not turn them into new V236 failures. Regeneration is not proof
that every visual change is desirable; preserved review assets support the
main visual review. This sidecar did not perform a fresh pixel/audio review.

Earlier red diagnostics (`integration-first`, `layout-hotseat-first`,
`auth-regression`, `auth-layout-final`, `focused-integration`, `focused-recheck`)
remain historical execution evidence. A filename containing `final` is not
itself a success signal. Locale setup, async fake assertions, list visibility,
spinner/semantics/timer timing and intentional consent/copy setup changes are
distinguished from product defects in the handoffs and findings. The later
broad and affected logs determine their applicable automated closure.

## Scope Of The Final Flutter Evidence

`learning-reconciled.txt` actually loads four files:

- `test/v230_learning_ui_test.dart`
- `test/v235_learning_acceptance_test.dart`
- `test/v236_tutorial_layout_test.dart`
- `test/online_deleted_session_recovery_test.dart`

`flutter-affected-final.txt` loads those four plus:

- `test/battle_ui/visual_test.dart`
- `test/v236_battle_readability_test.dart`
- `test/v236_hotseat_screen_test.dart`
- `test/v236_account_restore_ui_test.dart`
- `test/v236_font_licenses_test.dart`

The earlier [critical UI rerun](critical-ui-recheck.txt) also ends 74/0; it
overlaps these suites and the broad run, so is not added as extra coverage.
Deck, native Google credentials/restore, hotseat pure/privacy, account ownership,
economy recovery and online controller suites are listed in the broad manifest;
none is among that run's 51 failures except the explicitly identified fake-load
failure. This does not mean those files all ran again after every final edit.

Battle-after and tutorial directories each contain 30 PNG/JSON pairs matching
TR/EN x five viewports (320x568, 360x640, 390x844, 430x932, 768x1024) x scales
1.0/1.3/2.0. `menus/` contains 90 PNG/JSON pairs for 62 tests, including scrolled
tails; image count is not test count. Menu fixtures are principally 390x844,
scale 1.0 and explicitly identify themselves as local deterministic fixtures.
They are neither HTML stand-ins nor live Firebase screenshots, and do not
establish the complete acceptance viewport/state matrix for every screen.

## Backend, Rules And Differential Evidence

Backend TAP tail: `tests 1268`, `pass 1267`, `fail 0`, `skipped 1`.
Skipped case: **V220 actual isolated RTDB integration (Auth, App Check and Play
remain mocked)**. Static source/rule/index assertions and in-memory DB adapters
are not executed Firebase security rules, real transactions or deployed parity.

[Backend handoff](backend-handoff.md) originally marked three economy route
tests NOT RUN. Later TAP cases 1264-1266 are all `ok`: orphaned onboarding
credit rejection, daily cursor/claim loss rejection, valid onboarding cache-loss
replay. Its helper cases 1254-1263 and static notification index case also pass.
The worker's earlier focused 16/0 result overlaps this suite. See
[ECONOMY_REPORT.md](ECONOMY_REPORT.md) for the fault-injection boundary.

Current TS rules tail: `tests 376`, `pass 373`, `fail 0`, `skipped 3`.
The skipped tests remain explicitly NOT RUN in this invocation:

- `fresh Dart/TS rejects the same coerced target payloads`
- `fresh Dart/TS targeted terminal differential`
- `fresh Dart/TS compare raw equivalent and malformed card target JSON`

The separately executed [differential log](differential-run.txt) and
[current JSON](differential/v201a-differential-summary.json) show:

| Metric | Observed value |
| --- | ---: |
| Scenarios | 3101 |
| Compared states | 10967 |
| Compared legal-action sets | 10967 |
| Legal-set divergences | 0 |
| Resulting-state divergences | 0 |
| Repetition checks | 12 |
| Redaction checks | 3820 |

All 56 positive minima and 188 rejection minima are satisfied in that JSON.
The old `v201a` output basename is a generator convention, not an old log being
passed off as current. This broader differential run does not retroactively
unskip the three distinct targeted tests. Agreement between engines is not
independent proof of every rule or human balance. Actual card stress, fixture
and combination links are in [CARD_COVERAGE.md](CARD_COVERAGE.md).

## Command Provenance

Commands below describe retained execution, **not commands run by this
sidecar**. [run-regression.ps1](run-regression.ps1) records the original Flutter
launcher: repository Dart executable + Flutter tool snapshot, `test --no-pub
--concurrency=1`, the saved sorted 117-file list, `--reporter expanded`.

[run-final-gates.ps1](run-final-gates.ps1) records these exact argument shapes
(paths shown relative to the stated working directory):

```powershell
# Flutter root; $Dart and $Snapshot are the paths saved in the launcher.
& $Dart $Snapshot test --no-pub --concurrency=1 --reporter expanded --update-goldens test/battle_ui/visual_test.dart --name '^visual state'
& $Dart $Snapshot test --no-pub --concurrency=1 --reporter expanded test/battle_ui/visual_test.dart test/v236_battle_readability_test.dart test/v236_tutorial_layout_test.dart test/v230_learning_ui_test.dart test/v235_learning_acceptance_test.dart test/v236_hotseat_screen_test.dart test/v236_account_restore_ui_test.dart test/v236_font_licenses_test.dart test/online_deleted_session_recovery_test.dart
& $Dart $Snapshot test --no-pub --concurrency=1 --reporter expanded --dart-define=LUNO_QA_CAPTURE_DIRECTORY=qa/v236/menus test/rc_screen_capture_test.dart
& $Dart run qa/v236/export-cards.dart
# functions/rules-v1; $Node is the repository Node 22 executable.
& $Node --test --test-concurrency=1 'dist/test/*.test.js'
& $Node dist/test/differential.js
```

The differential launcher sets `LUNO_DIFFERENTIAL_QA` to `qa/v236/differential`
and `LUNO_DART_RUNNER` / `LUNO_DART_RUNNER_ARGS` to the repository Dart runner,
package config and `tool/battle_json_runner.dart`. No live transport is involved.

[typescript-build.txt](typescript-build.txt) records `npm run build:battle` ->
`npm --prefix rules-v1 run build` -> `tsc`. The backend TAP file does not retain
its full shell argv; `node --test test/*.test.js` is the package's documented
equivalent from `functions`, not proof of unrecorded heap/concurrency flags.
The learning log proves its four loaded files and 89/0 tail, but its full
original shell command is not retained. No missing command detail is invented.

[analyze-final-source.txt](analyze-final-source.txt) ends `No issues found!`
for 119 analysis items. Its launcher selects `lib`, the saved test list and
`tool/rc_product_inventory.dart`; this is not a repository-wide analyzer claim.
Reference generation, analysis and TypeScript compilation are separate gates,
not additional test-case passes.

## Source Identity And Acceptance Boundary

[source-lock.json](source-lock.json) records 1963 selected source/backend/asset
files; recorded SHA-256 at reconciliation:
`634D97252790E9CFCFE75E94ECD7CC3AE2B246CF2F140E85A1C17898C5262202`.
The manifest is not a committed clean-tree identity. Read-only spot checks here
matched 15 entries: Dart card model/core/timing/layout, both learning tests and
recovery fake, TS model/core, backend catalogs/Pass/chests/economy/index and
selected production rules. This is **not a fresh all-1963-file freeze check**
or proof that every retained run used precisely the final frozen tree.

[source-freeze-build.txt](source-freeze-build.txt) records the 1963-file freeze
and preservation of 803 original art/font/audio/iOS inputs.
[protected-core-result.txt](protected-core-result.txt) records 12 engine/rules
inputs matching V235 hashes. These are retained checks, not claims of work
performed anew by this sidecar. The main owner must verify the final freeze
and associate final artifacts with it after any further source edit.

`apk-build.txt` currently contains build progress/warnings but no success tail;
it alone does not prove a completed APK. No AAB success evidence was established
by this sidecar. Package filenames, sizes, hashes, signature, alignment and
build completion must come from main's final artifact report. No previous APK
is asserted to contain these fixes.

| Acceptance area | Status here | Remaining boundary |
| --- | --- | --- |
| Stated local rules, stress, differential and affected regressions | PASS, scoped | No complete final green 117-file rerun recorded |
| Tutorial / hotseat / auth / economy / social / online mocks | PASS, scoped | Does not replace native/provider/two-client acceptance |
| Flutter capture generation and golden comparison | PASS, scoped | Full manual visual/VFX/audio acceptance not established here |
| Real Google restore, second device, App Check / Play Integrity | BLOCKED | No live/native acceptance performed |
| Two-account/two-device online, deployed backend parity and real Firebase rules | BLOCKED | Isolated integration skipped; no live acceptance |
| Real Android install, TalkBack, system back, lifecycle and complete player journey | NOT RUN | Physical device acceptance unavailable |
| Release FPS/RAM/thermal/battery and long-session audio/VFX | NOT RUN | Widget/debug evidence is not release-device measurement |
| Final APK/AAB, signature and static 16 KB package checks | Main-owned, not accepted here | Incomplete local build log is insufficient |
| Real 16 KB runtime | NOT RUN | Static package alignment cannot establish runtime acceptance |
| Play license purchases, refunds/RTDN/subscriptions and test-track install | NOT RUN | No real purchase or Play upload performed |

**RELEASE HOLD.** Automated closure does not supply unavailable device/live/Play
acceptance. No readiness score, zero-defect guarantee or fictional combined
test total is issued.
