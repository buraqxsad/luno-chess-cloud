# V236 Deck Handoff

## Final Follow-Up: Context Guards

Main reports all deck cases passed the focused recheck. Analyze then identified `use_build_context_synchronously` at the discard/save exit sites in the current, formatted `battle_deck_screen.dart`.

Final incremental edits are limited to that source file and this handoff: after the dialog await, the existing `_canAct` check now explicitly checks `mounted`; after the save await, an explicit `if (!mounted) return` precedes the existing confirmation/account/dirty checks and navigation. No save, draft, ownership, metrics, or test expectations changed in this step.

No SDK command was run by this worker. Post-guard analyzer confirmation remains main-owned. Current `lib/screens/battle_deck_screen.dart` SHA-256: `742B900759336111D79365BB63A3C46EEE4AD44DF834FE953C36D902EFDB49CA`.

## Incremental Follow-Up: Integration First

Evidence reviewed: main's `qa/v236/integration-first.txt`. It records 5/5 V236 metrics tests passing and 23/25 V236 navigation cases passing. The two navigation failures are exact-text finders for the save status and rights validation after conditional `ListView` rows change. The first case had already passed its three-read/one-write assertions; the second had passed draft retention and disabled-save assertions.

Incremental edits, with no production source changes:

1. `test/v236_deck_navigation_test.dart`: both failing cases now reset the main scroll position and scroll to the stable message key before retaining the original exact-text expectation. Added explicit account-deck, rights, error, completed-saving, and read-count assertions to distinguish lazy rendering from broken reconciliation. No expectation was removed or weakened.
2. `test/v214_active_deck_test.dart`: authorized single-Freeze expectation now asserts incomplete draft classification and no complete-deck heavy warning. All curve assertions remain.
3. `test/v216_progression_ux_test.dart`: only the five documented old-copy expectations were updated to the exact ambiguous-save message. Save counts, draft retention, retry, success, stale-result, and overflow assertions remain unchanged.
4. This handoff: incremental evidence/status and file hashes updated.

The log and source point to a lazy-list visibility problem in the two new cases, not a demonstrated production failure. The stronger state assertions and explicit scrolling still require main's SDK rerun; this worker ran no SDK command. Production file hashes remain identical to the initial handoff.

## Scope And Baseline

- Root: `C:\Users\Casper\Documents\Luno Chess\luno-chess-src\luno_chess`.
- Read the full attached acceptance request, with implementation limited to section 6.
- Source version read from `pubspec.yaml`: `1.6.3+18`; unchanged.
- Git HEAD: `9e0ab47f913a5a20146a4c64e5858b5dd77bf304`, plus extensive pre-existing dirty/untracked work. HEAD is not a clean source identity.
- No applicable `AGENTS.md` was found in ancestor directories or the scoped `lib`, `test`, and `qa` trees.
- Existing account guards, catalog powers/costs, ownership validation, assets, iOS, economy, signing, and version configuration were preserved.
- No SDK, build, local server/port, Firebase mutation, deploy, or deletion was run by this worker.

## Changed Paths

- `lib/screens/battle_deck_screen.dart`
- `lib/battle_v1/deck_metrics.dart`
- `test/v236_deck_metrics_test.dart` (new)
- `test/v236_deck_navigation_test.dart` (new)
- `test/v214_active_deck_test.dart` (authorized follow-up assertion only)
- `test/v216_progression_ux_test.dart` (authorized follow-up copy assertions only)
- `qa/v236/deck-handoff.md` (this note)

## Confirmed Findings And Fixes

### DECK-01: Unsaved navigation silently lost the draft

Reproduce in the pre-fix source: open Deck, remove Purify, add owned Fog, then use the app-bar back button or Android back. The screen had no exit guard, despite displaying an unsaved status.

Fix: one guarded exit flow for app-bar back, system back, and `Navigator.maybePop`, with Save, Discard changes, and Keep editing. Invalid drafts show the reason and disable Save. A failed save does not leave. Pending saves block exits and repeated writes. Account-owned dialogs and current-route checks prevent stale actions from popping unrelated routes.

Tests: navigation source x save/discard/cancel matrix; clean exits; nine-card invalid draft; compact TR/EN dialog at 320x568 and 2.0 text; pending-save double back/double write.

### DECK-02: Lost or malformed save response had no reconciliation

Reproduce in the pre-fix source: commit a valid deck on the server but throw, time out, or return malformed acknowledgment to the editor. The editor always said the deck was not saved, without checking server state. The existing code already retained the draft on a failed save; that is not claimed as a newly discovered data-loss bug.

Fix: failed acknowledgment triggers one bounded, validated server read. Exact ordered deck equality confirms success; a mismatched/read-failed result preserves the selected draft and gives an honest unconfirmed status. Check save repeats only the read, without another write. A reconciliation read may update the server baseline/rights but never replaces the draft. Selected cards can still be removed if refreshed rights no longer allow them.

Tests: failed save and successful retry; committed write with lost/malformed/timed-out response; failed read then explicit read-only recovery; refreshed rights; account switch during dialog, write, and reconciliation. Stale account results are ignored through the existing auth/store epoch guard plus request generation.

### DECK-03: Heavy warning was unreachable for every legal deck

Current canonical cost histogram: `{1: 5, 2: 12, 3: 5, 4: 1, 5: 1}` across 24 unique card IDs.

- Minimum legal total: `5*1 + 5*2 = 15`; average `1.5`.
- Maximum legal total: `5 + 4 + 5*3 + 3*2 = 30`; average `3.0`.
- Therefore average `>= 3.5` cannot occur in any ten-unique-card deck. Taking the sorted extremes is exact: exchanging a chosen card with a cheaper/more expensive unchosen card cannot worsen the corresponding bound.
- Independent lightweight PowerShell enumeration of all 139 feasible cost-count compositions also produced totals 15..30 and 3..10 opening-affordable cards.

Fix: heavy now means a strict majority costs more than the first card phase's two mana: six or seven cards at cost 3+ in a complete ten-unique deck. Five expensive cards do not warn. Incomplete, duplicate, and oversized selections are drafts, not complete deck evaluations. Added opening affordability, 4+ cost density, reactive removal, sacrifice requirements, and piece-specific requirements. The editor distinguishes affordability from actual legal targets/conditions. Existing mana curve is retained; no game power or cost was changed.

Tests: independent catalog histogram/extreme totals, first legal card phase through real local-session chess moves, five/six expensive-card boundary, invalid drafts, and condition counts.

## Verification

- PASS: light source inspection; exact histogram/bounds from current `model.dart` using PowerShell; independent grouped-composition enumeration; scoped trailing-whitespace scan with `rg` (no matches).
- New tests were written before the initial production fixes. No pre-fix red run was performed by this worker; passing focused results are reported by main, not by an SDK run here.
- NOT RUN by this worker, per explicit constraint: all Flutter/Dart SDK commands, formatter/analyzer, unit/widget execution, rendering/screenshots, APK/AAB, live Firebase, and physical Android acceptance.
- Main's first integration log records the 5 focused unit tests passing and 23 of the 25 parameterized widget cases passing. Main subsequently reports all focused deck cases passed after the harness/legacy-assertion edits. Only the final context-guard step has no post-edit SDK confirmation in this handoff.

## Main Integration Status

The user authorized the exact two previously requested legacy-test edits. Both are now applied:

1. `test/v214_active_deck_test.dart`: single-Freeze draft is explicitly incomplete and not heavy; surrounding curve checks retained.
2. `test/v216_progression_ux_test.dart`: three presence and two absence expectations now use the exact unconfirmed-save copy. All behavioral assertions are retained. This is a semantic correction for ambiguous writes, not a weakening of those regressions.

Previously requested serial rerun suites (main now reports focused deck recheck passing):

```text
flutter test --concurrency=1 test/v236_deck_metrics_test.dart test/v236_deck_navigation_test.dart
flutter test --concurrency=1 test/battle_deck_account_test.dart test/rc_deck_navigation_owner_test.dart test/v214_active_deck_test.dart test/v215_deck_replacement_test.dart test/v216_progression_ux_test.dart
```

Main should also format/analyze the scoped files and run the broader integrated gates when resources permit.

## Remaining Risks And Acceptance

- Focused deck cases are PASS as reported by main. Post-guard analyzer confirmation and broader integrated gates remain main-owned, not claimed here.
- A read immediately after a timed-out write can still see the previous deck. The editor keeps the draft and offers another explicit check; it does not falsely confirm or automatically repeat the write. The service retains responsibility for its underlying in-flight request/cache ordering.
- No new process-death draft persistence was introduced. Explicit navigation is protected; app termination is not claimed to restore an unsaved editor draft.
- Destructive external route removal/account-scope replacement is not converted into a user save prompt; account changes intentionally invalidate the previous account's draft.
- Actual Android predictive/system back gestures, real network ambiguity, live account switching, and visual layout remain NOT RUN.
- New validation/analysis copy and the exit dialog require an intentional visual review; do not blindly accept changed golden images.
- No APK/AAB was created. This worker does not grant release approval; required device/backend/Play gates remain with main and the overall RELEASE HOLD.

## Historical SHA-256 Before Main Formatting

```text
lib/screens/battle_deck_screen.dart 868B4507880F93FB34B6B1DC94AC82022F852DFF38E17D9A3320FF7C13827506
lib/battle_v1/deck_metrics.dart A4C938DE0EDF24FCCF07A3283CD70DB89A10AC3820B098BFCD8EB47DCCC33B63
test/v236_deck_metrics_test.dart CFAD2D1E24B0EC792A46A4BB80FE451D6A5E373766E8C19352007B80CEB12F65
test/v236_deck_navigation_test.dart 5F18315FC73D21C3FA768C9AD7578D46AB02F4952AC6AF074B0AE3BFF7536836
test/v214_active_deck_test.dart B75C65FE8E23C62660E2D975AB0BC7D9CCBD8EAD3FE079B7AE972138D8818AB5
test/v216_progression_ux_test.dart E21BD496848E11F607104337E91CE6C7FC7F5D435C6D91A352515F09526316D1
```
