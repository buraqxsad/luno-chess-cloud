# Round 4 battle interaction audit

One NEW P2 defect family was reproduced and fixed: a queued sheet opener could label an obsolete private projection as current. One additional regression closes a compact-layout path omitted from the round 3 stale-selection fix; that residual is not counted as a new defect family.

Baseline owned runtime: `d67cd449cbd8834a4878f5484941d376fa7c17d8`, branch `codex/cloud-transfer-20261027`. Only `luno_chess/lib/screens/battle_v1_screen.dart` and the two new `round4_battle_*.dart` tests are owned by this audit. Other agents' shared-worktree edits were left alone.

## Reproduction and controls

The real BattleV1Screen, controller, projection and Dart rules run through the existing fixture transport. All authority transitions are independently admitted by `BattleRulesCore.isLegalAction` before applying them with `DeckManager.apply`. No golden or replacement independent oracle is introduced.

- Cast Prophecy and resolve its two-card order, initially Radar then Slow. Retain the real forecast opener. Advance the authority through e2e4 and e7e5 and reconnect; the white draw consumes Radar, leaving only Slow in the upcoming order. Invoke the retained opener before the next painted frame. Baseline displays Radar then Slow as still upcoming.
- Retain the own-deck opener before the same legal draw. Baseline restores the old own-hand membership and deck counts in its sheet, omitting the newly drawn Radar.
- The current forecast and deck openers show current content after the draw; a retained forecast opener remains usable across a harmless same-version reconnect. All three controls passed at baseline.
- At 360x568 with text scale 1.2, retain the compact Pass icon, select Shelter before rebuilding, then invoke Pass. Baseline submits a Pass despite the new selection. A current unselected compact Pass still submits exactly once under duplicate invocation. This is the prior round 3 family on an omitted layout path.

Final valid pre-edit baseline: **4 pass / 3 fail**, exit 1, seven tests in `rawlogs/battle-before.log`. Two failures demonstrate the new overlay family; one demonstrates the residual compact command path. Earlier harness compile, forecast-count and compact-size errors are preserved in separate logs and are not counted as product failures.

## Fix

The existing sheet admission guard now accepts the version of the view that supplied its content. All six frame-derived content openers pass that version: forecast, radar and knowledge toolbar, own deck, practice deck, and next-action explanation. A queued old projection is rejected before opening a route; the existing account, route, lifecycle, hotseat epoch, first-builder and in-flight snapshot checks remain in force. Same-version refreshes still permit unchanged openers.

The compact Pass icon now uses the same `_selectionCommand` admission wrapper as the normal Pass button. No rules, balance, action protocol, clocks, production audio, artwork, animations or goldens changed.

## Verification

Pinned `/workspace/toolchains/luno-env.sh`, shared Flutter flock, `--no-pub --concurrency=1 --reporter=expanded`:

```text
test/round4_battle_knowledge_test.dart
test/round4_battle_compact_pass_test.dart
test/round3_battle_selection_test.dart
test/rc_battle_modal_ownership_test.dart
test/v236_hotseat_screen_test.dart
test/tutorial_luno_live_test.dart
test/v223_accepted_frames_test.dart
test/v216_1_battle_emote_integration_test.dart
```

**122 pass / 0 fail**, exit 0, eight files; the seven new tests are included in 122. `rawlogs/battle-after-related.log` retains the output. `git diff --check` passed for the owned files. No untracked QA PNG/JSON files were generated.

Source review also followed board target admission, pending promotion/action sheets and cancellation, private resolution, hotseat conceal/reveal, tutorial completion and route/lifecycle cleanup, accepted-frame replay suppression and emote ownership. Passing evidence is limited to the named cases. The visual agent's timeout concern was withdrawn after reading the full-resolution pair: both reference and candidate show Victory / Time expired, consistent with that fixture; it is not a defect.

This is bounded widget/controller/rules verification with fixture transport and mocked audio platform channels. No full suite, analyzer, build, emulator, production service, payment, upload, signing, deploy or push was run. Device/performance/service acceptance and existing release holds remain outside this result.
