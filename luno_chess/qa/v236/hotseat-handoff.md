# V236 Hotseat Privacy Handoff

## Status and Scope

- Implementation and test authorship complete; SDK execution intentionally left to the main worker, serially, on the 8 GB machine.
- Flutter/Dart analysis, formatting, unit/widget tests, device tests, screenshots, APK and AAB: NOT RUN by this worker. No passing-test or compile-success claim is made.
- Source review reproduces two P1 privacy defects. Runtime reproduction and regression acceptance remain NOT RUN until the commands below are executed.
- Root: `C:\Users\Casper\Documents\Luno Chess\luno-chess-src\luno_chess`.
- Shared dirty worktree base HEAD: `9e0ab47f913a5a20146a4c64e5858b5dd77bf304`. HEAD alone does not identify the extensive dirty/untracked source.
- Observed pubspec version: `1.6.3+18`; unchanged.
- Full attached request was read, with implementation restricted to section 5 and assigned files. Applicable ancestor/root/lib/screens/lib/battle_ui/test/qa AGENTS checks found none.
- No engine, rules, economy, services, settings, auth, deck editor, assets, Android/iOS configuration, signing, version or live Firebase changes. No local server, reset, revert, SDK process or build was started.

## Reproduction Before the Fix

Baseline battle screen SHA-256 before production edits:
`CB26DAEC003D922D90E3BE506939D0F96FE4C5EF95FAAC0B991259F2EF12E77E`.

The light PowerShell source probe returned:

| Probe | Before |
| --- | --- |
| Local authority projects `hotseat ? board.turn : white` immediately | true |
| Screen binds the current projection directly into `BattleHand` | true |
| Handover/privacy curtain exists in battle screen | false |
| Lifecycle callback clears selection or private sheet ownership | false |

This is source-level reproduction, not a rendered-device or executed-widget reproduction. Tests were added before the production edits, but an executed red run was deliberately not attempted under the no-SDK instruction.

### HS-01: Incoming Hand Exposed at Turn Change (P1)

- Files/functions: `lib/battle_v1/local_session.dart` (`view`, `_apply`) and `lib/screens/battle_v1_screen.dart` (`_changed`, `build`, `_handHeader`). Engine file was read only.
- Reproduce: start local two-player play, inspect White's initial hand, play `e2e4`, keep holding the device. The authority switches viewer to Black and notifies; the screen immediately renders Black's hand and own-deck access without consent. Reverse after `e7e5` has the same issue. The same exposed widgets contribute card labels to semantics.
- Root cause: no presentation admission boundary exists between the authority's player projection change and mounting the new private UI.
- Fix: initial White, each color change and each rematch are concealed. A full-screen handover replaces the complete battle presentation subtree rather than painting a cover over retained private widgets. Private hand/deck/knowledge, semantics, card previews and animation widgets are absent until a fresh acknowledgement.
- Regression: actual board taps cover White -> Black -> White, stale board/deck callbacks before and after acknowledgement, missing private widgets and missing hand/deck/all-card semantics.
- Residual risk: physical Android screenshot/app-switcher timing and actual TalkBack traversal require device acceptance.

### HS-02: Background Return Retains Private Presentation (P1)

- File/functions: `lib/screens/battle_v1_screen.dart` (`didChangeAppLifecycleState`, `_sheet`, `_privateChoice`).
- Reproduce: reveal a local hand; open own deck, card detail, tooltip or Prophecy/Fate Exchange choice; background and resume without ending the turn. The old lifecycle callback only reset presentation trackers and observation; it did not demand consent or clear the private sheet/selection.
- Root cause: lifecycle visibility was treated as timer/animation observation, not as revocation of private presentation consent. Private modal closures retain their captured projection.
- Fix: every non-resumed lifecycle state revokes consent, clears selections, target state, exchange animation origin, draw/presentation histories, tooltips, focus and emote presentation. The owned modal route is removed without a reverse animation. A listenable modal guard hides content even if lifecycle changes before the modal's first build or while a prior route is reversing. Resume never acknowledges automatically.
- Stale callback/results: viewer/lifecycle/rematch epochs reject old ready callbacks, private sheet results, hand/deck/knowledge callbacks and board taps. Accepted-action continuations and private exchange origin updates also check their epoch. Current card actions capture their build's selected card/action rather than dereferencing cleared selections.
- Pending-card contract: presentation cleanup does not resolve, reorder, discard or cancel an authoritative pending card transaction. The same player can acknowledge and explicitly reopen it. Seeded integration scenarios cover both Prophecy and Fate Exchange.
- Residual risk: process death does not restore an in-progress local match; that behavior is unchanged. A newly created local screen always starts concealed.

## Clock Contract

- The active player's existing monotonic match clock runs during initial consent and handover, with the existing time control/increment unchanged.
- The privacy gate never calls `observe(false)` merely because the curtain is visible. The battle route remains observed; the authority timeout timer can end the match while acknowledgement is withheld.
- Background observation still uses the existing session behavior: callbacks stop, but elapsed time is not refunded. Resume reconciles timeout before play.
- Ready admission explicitly calls `checkTimeout()` before revealing. An expired curtain proceeds to the public terminal screen, not a newly revealed hand.
- The curtain uses the existing active `BattleClock` widget and states that the active clock keeps running.
- Tests independently cover monotonic elapsed time/background timeout, a repainting curtain clock, and a full-screen injected-authority incoming timeout without acknowledgement.

## Authored Tests

`test/v236_hotseat_privacy_test.dart`:

- Per-player and per-lifecycle epoch consent.
- Wrong viewer, stale generation, duplicate acknowledgement and pre-rematch callback rejection.

`test/v236_hotseat_screen_test.dart`:

- Real `square-12` -> `square-28`, acknowledgement, then `square-52` -> `square-36` taps.
- Initial White and incoming Black concealment, reverse handover, clean selections.
- Semantics checks for localized hand/deck/arsenal/private/upcoming labels, own-deck tooltip and every canonical card name, including Prophecy, before acknowledgement.
- No mounted private hand/card/board/cast/draw/private-sheet subtree behind the curtain, including offstage widgets.
- Selection, own deck, card detail and tooltip interruption through inactive/paused/resumed lifecycle states.
- Seeded Prophecy and Fate Exchange pending-choice modal interruption; authority state unchanged; explicit reopen/resolve; old private knowledge callback rejected after the next player acknowledges.
- Lifecycle interruption before a sheet's first build, without leaving an empty blocking route.
- Stale ready callback, real result-rematch button and fresh concealed match.
- Authoritative elapsed clock and timeout; active curtain clock repaint; incoming timeout while the curtain is retained.
- TR/EN curtain reachability at 320x568 and 430x932 with 2.0 text scaling.

`localSessionOverride` is an explicitly testing-only seam parallel to the existing controller override. Injected sessions are caller-owned; rematch creates a fresh production session and does not reuse the injected authority. This allows deterministic hidden-card and clock tests without changing the engine.

## Exact Serial Verification

Run from the root above. Do not overlap these commands with any other SDK/build/test process.

```powershell
dart format lib/screens/battle_v1_screen.dart lib/battle_ui/hotseat_privacy.dart test/v236_hotseat_privacy_test.dart test/v236_hotseat_screen_test.dart
flutter analyze --no-pub lib/screens/battle_v1_screen.dart lib/battle_ui/hotseat_privacy.dart test/v236_hotseat_privacy_test.dart test/v236_hotseat_screen_test.dart
flutter test --no-pub --concurrency=1 test/v236_hotseat_privacy_test.dart test/v236_hotseat_screen_test.dart
flutter test --no-pub --concurrency=1 test/v235_gameplay_lifecycle_test.dart test/v221_offline_lifecycle_test.dart test/v228_battle_interaction_regression_test.dart test/v232_battle_motion_boundaries_test.dart
```

Two existing suites assume a local hand is visible immediately. They are outside this worker's ownership and were NOT edited:

- `test/battle_ui/lifecycle_accessibility_test.dart`: local rematch scenario must tap `hotseat-ready` after initial load and after `local-rematch`, preserving its existing board/hand/phase/clock expectations.
- `test/v216_1_battle_emote_integration_test.dart`: hotseat scenarios need an initial `hotseat-ready` tap before their existing emote-boundary steps. Keep the original audio/visibility expectations.

After those intentional setup updates, run:

```powershell
flutter test --no-pub --concurrency=1 test/battle_ui/lifecycle_accessibility_test.dart test/v216_1_battle_emote_integration_test.dart
```

Do not remove privacy assertions to make these suites pass. The new initial-consent boundary is intentional behavior.

Integration note: main's `qa/v236/google-restore-before` captured a transient missing `battle_learning_copy.dart` extension import while this implementation was in progress. That import is now present. The new semantics test also imports `battle_v1_copy.dart` explicitly. The transient compile result is not an app baseline regression and is not evidence that the final source compiles.

## Manual Android Acceptance Still Required

1. Verify White initial consent, handover after every accepted move, Black/White direction, and rapid taps near the ready/board positions.
2. With TalkBack, confirm no card, hand, own-deck count or upcoming-card node is reachable while concealed. Repeat from private modals and pending choices.
3. Background from hand, deck, card detail, tooltip and both pending-card flows. Resume through recents, notification shade and screen lock; require fresh consent each time.
4. Hold the curtain past flag fall, including background time. Confirm the active player loses on time and cannot recover time by acknowledging late.
5. Finish and rematch, leave and open a fresh local match, and kill/relaunch the process. No prior hand should auto-reveal; no local-match persistence was added.
6. Inspect TR/EN at 320x568, 360x640, 390x844, 430x932 and tablet, text scales 1.0/1.3/2.0, including landscape/split-screen. The new automated layout matrix is bounded to the four language/size cases above, not the complete device matrix.
7. Inspect actual card/draw/exchange animations across handover and lifecycle boundaries. Widget absence assertions are not pixel/audio acceptance.

## Light Checks Actually Performed

- Full request read, applicable AGENTS discovery, dirty Git inventory, targeted engine/controller/widget/test source inspection, and before-fix source probe.
- Read V235 report references for context only; no old test/build result was reused as current evidence.
- Explicit trailing-whitespace scan of all four authored Dart files: zero trailing-whitespace lines at the check.
- `git diff --check -- <owned Dart paths>` returned exit 0. These files are untracked in the shared baseline, so that Git result alone does not validate their contents.
- No Flutter/Dart SDK command, test suite, formatter, server or Android build was run by this worker.

## Modified Paths

1. `lib/screens/battle_v1_screen.dart`
2. `lib/battle_ui/hotseat_privacy.dart` (new)
3. `test/v236_hotseat_privacy_test.dart` (new)
4. `test/v236_hotseat_screen_test.dart` (new)
5. `qa/v236/hotseat-handoff.md` (new)

Acceptance: implementation authored; SDK/device validation NOT RUN. Hotseat acceptance remains pending. This worker does not grant Android release approval; RELEASE HOLD remains appropriate until the main acceptance gates are completed.
