# Battle/tutorial bug hunt

**1 new P2 production defect reproduced and fixed.** A real battle update arriving between a modal opening and its first builder left an obsolete private deck/choice sheet visible. `_changed()` could only remove `sheetRoute` after a builder assigned it; the lazy builder itself checked account/hotseat ownership but not the match snapshot. The same missing match listener kept an already-visible stale child painted for the first invalidated frame.

`battle_v1_screen.dart` now captures the opening version/terminal state, observes the current controller/local session in the existing sheet gate, and hides an obsolete child before painting. Exact-route cleanup remains deferred and guarded, preserving unrelated routes. The existing V238 account-change, returned-account, hotseat and late emote protections are retained.

New `test/system_hunt_battle_sheet_version_test.dart`: version update and terminal transition both before the first builder and after the sheet is visible, plus a current-sheet usability control. **Before: 1 pass / 4 fail**; all four real repros observed the obsolete child on the first paint. **After: 5/5**. Combined with unchanged V238 sheet ownership (4), V238 emote ownership (5) and modal ownership/admission (8): **22/22 PASS**, exit0, 62s. The valid pre-fix log is `sheet-before.log`; an initial test-fixture constructor typo is separately retained as `invalid-first-fixture.log` and is not counted as a bug reproduction.

Command (inside the shared Flutter flock and pinned luno-env):

```bash
flutter test --no-pub --concurrency=1 test/system_hunt_battle_sheet_version_test.dart test/v238_battle_sheet_owner_test.dart test/v238_emote_picker_owner_test.dart test/rc_battle_modal_ownership_test.dart
```

Also inspected hotseat acknowledgement/epoch admission, private choice callbacks, emote send/late-response ownership, accepted VFX history reset, mentor lifecycle and central audio queue/scene/lifecycle logic. No additional new defect is claimed from that inspection. No new animation feature, game-rule edit, fixture/golden overwrite or assertion weakening occurred. Only the battle source file above and one new regression file were changed by this agent. No generated QA PNGs were produced by these tests.

These are Flutter widget tests with fixture transport, not native Android, production Firebase, physical audio/GPU, or Google Play acceptance. No emulator, full suite, build, deploy, payment, upload, push or commit was performed.
