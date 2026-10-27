# V235 - Final Gameplay, Tutorial and Android Quality Pass

## Decision

**RELEASE HOLD for production publication.** The targeted source fixes and
static Android package gates passed. Physical Android runtime, production
App Check/Play Integrity and a real two-player online acceptance run remain
unverified. These are evidence gaps, not newly reproduced failures, and must
not be reported as passed.

This implements the user's V226 request on the latest post-V234 Flutter
source, labelled V235 to avoid replacing newer work. Most evidence was
generated on October 14-15, 2026; final source/package reconciliation and a
fresh broad Flutter regression were performed on October 22, 2026.

## 1. Confirmed Fixes

### Guided learning could require a full match and mistake an implicit pass for learning

The first guided Baby Luno match now completes after four accepted chess
moves, a targeted card play, a discard and an explicit card-pass action.
Moving a chess piece directly may implicitly pass the card phase, but no
longer marks the explicit pass lesson as learned. Winning a full AI match is
not required. The completion CTA pauses further AI activity before exit.

Progress is saved locally per account as learned skills. Account changes
reject late progress/skip callbacks. Skipping is confirmed and idempotent;
replaying the basics does not overwrite onboarding progress. Neither route
grants currency, trophies or career match results.

### Clock expiry could publish an already-rejected local action

LocalSession previously assigned the candidate rules state before confirming
that the acting player's clock allowed the action. Clock expiry during that
commit could expose a move/card action which should have lost on time.
The clock gate now precedes publication. Rejected commits do not continue
the AI turn. Resignation also rechecks timeout before assigning the winner.

### Installed Android build and online descriptor disagreed

Source declared build 17, generated Android metadata used 18 and the online
descriptor always sent 17. Source is aligned to 1.6.3+18 for these local QA
packages. Android online descriptors now obtain the installed PackageInfo
identity through a native channel rather than trusting a hardcoded build.
An account change while awaiting that lookup prevents dispatch under the
next account. Malformed native metadata is rejected, not replaced with 17.
The game protocol remains LUNO_BATTLE_V1 and is independent of app build.

### Signing backups were insufficiently excluded from source exports

Git/export policies now reject signing properties and renamed keystore
backups before reading candidate export files. Safe example templates remain
allowed. Synthetic-path regression checks passed; no credential values were
printed. Existing signing identity was preserved and checked on the packages.

### Two QA defects were corrected without changing game rules

- Six V223 assertions rejected whole-valued JSON numbers even though approved
  V224 wire normalization accepts equivalent JSON spellings. Assertions now
  compare the complete resulting authoritative state. Typed doubles,
  fractional numbers, strings and malformed actions still reject atomically.
- The screenshot helper could overscroll a lazy shop list and capture a blank
  tail. It now validates scroll range before stopping. The new failing range
  assertions were run first, then both languages passed after the helper fix.

The tutorial completion regression was also executed before its production
fix. Other new cases were authored before the fixes but were first executed
by the main run after integration; an executed red-before run is not claimed
for every item.

## 2. Changed Files And Ownership

Paths below are relative to the Flutter project root.

| File | Reason |
| --- | --- |
| lib/battle_v1/practice.dart | Explicit learning checkpoint, accepted-action tracking, short guided completion |
| lib/models/game_store.dart | Account-scoped persistence, safe skip, archive/erase handling |
| lib/screens/battle_practice_campaign.dart | Onboarding/replay separation and progress callbacks |
| lib/screens/battle_v1_screen.dart | Explicit versus implicit pass, skip confirmation, finish/AI coordination |
| lib/battle_ui/practice_coach.dart | Phase-aware instructions and visible lesson goals |
| lib/screens/battle_welcome_screen.dart | Clear practical-training copy and safe skip entry |
| lib/screens/legacy_parity_screens.dart | Replay-basics entry only; existing Academy preserved |
| lib/battle_v1/local_session.dart | Clock-before-state commit and timeout/resignation ordering |
| lib/services/app_release_identity.dart | Validated installed Android version/build channel |
| lib/services/luno_online_service.dart | Installed build descriptor and ownership check after await |
| android/app/src/main/kotlin/com/luno/chess/MainActivity.kt | Native PackageInfo bridge and channel cleanup |
| pubspec.yaml | Align local QA version to 1.6.3+18 |
| android/.gitignore | Exclude signing files and backups, preserve templates |
| tool/package_source.ps1 | Harden source-export path filtering |
| test/v235_learning_acceptance_test.dart | Practical tutorial, resume, replay, skip, account and layout regressions |
| test/v235_gameplay_lifecycle_test.dart | Clock commit, resignation, suspended practice and late-AI cases |
| test/v235_release_identity_test.dart | Native identity validation and async account isolation |
| test/helpers/v223_fog_cases.dart | Reconcile old JSON expectations with V224 contract |
| test/helpers/v223_locked_square_cases.dart | Same wire-contract reconciliation |
| test/v223_rook_bend_adversarial_test.dart | Same wire-contract reconciliation |
| test/rc_screen_capture_test.dart | Isolated capture output and lazy-list overscroll assertion/fix |
| qa/v235-v226/* | Logs, captures, package audits, source locks and this report |

No original asset regeneration, card power/economy rebalance, iOS edit, live
Firebase configuration/deployment, player deletion or Play upload was done.
Existing unrelated tracked and untracked work was preserved. Of the 12
V234-protected core files, 11 remain byte-identical; only the documented
LocalSession clock fix changed the remaining file.

## 3. Tutorial Before And After

Before: loading/welcome entered the guided native Baby Luno match, but the
exit gate could keep a learner in a full match. Explicit card-pass learning
was not separately demonstrated, and the basics lacked safe skill checkpoint
resume and a dedicated reward-free replay entry.

After:

1. Existing loading and LUNO welcome are retained.
2. LUNO introduces a short practical, offline guided Baby Luno match.
3. The learner makes legal chess moves, selects/targets a card, sees mana and
   phase context, discards a card and explicitly passes a card turn.
4. The coach presents current goals and contextual guidance using actual
   control labels. Guided-first-match legal choices remain legal; educational
   filtering does not alter the card engine.
5. After the skills are demonstrated, the learner may continue without
   checkmating the AI. They may also confirm a skip and revisit the basics.
6. Local skill progress survives reopening; a resumed lesson starts on a
   fresh playable board. Exact mid-match board restoration is NOT provided.
7. The Guide offers a clean replay of the basics; the existing optional
   multi-stage Academy remains separate and unchanged in purpose.

TR/EN practical touch tests, partial resume through a new GameStore, account
replacement, replay and skip paths passed. Small-phone, large-text phone and
tablet layout cases passed. A first-minute timing guarantee on real hardware
has not been measured.

## 4. Test Evidence

The final broad Flutter run passed on October 22, 2026: 4631 passed,
0 failed across 92 files in 7 minutes 21 seconds. The result is recorded in
final-evidence.json and flutter-regression-final.txt. Initial and focused
results are retained, not overwritten.

| Check | Result / Evidence |
| --- | --- |
| Initial broad Flutter, 92 files | 4623 passed, 6 failed; flutter-regression.txt |
| Final broad Flutter, 92 files | 4631 passed, 0 failed; flutter-regression-final.txt |
| Final affected subset, 7 files | 632 passed, 0 failed; affected-verified.txt |
| Final learning acceptance | 19 passed, 0 failed; learning-final.txt |
| Flutter static analysis | No issues; analyze-verified.txt |
| Backend build | TypeScript build passed; typescript-build.txt |
| Backend tests | 1252 passed, 0 failed, 1 skipped; backend-regression.txt |
| Fresh-built TypeScript rules | 203 passed, 0 failed; typescript-rules-tests.txt |
| Dart/TypeScript differential | 3101 scenarios, 10967 states and legal sets; zero legal-set/state divergences |
| Differential privacy checks | 3820 redaction checks and 12 repetition checks |
| Menu render tests | 62 passed, 0 failed; 90 nonblank captures including scroll tails |
| ELF validator tests | 11 passed; validator correctness cases, not current package runtime proof |
| Source export/Git policy | Passed synthetic signing-file and backup exclusions |

Counts overlap and must not be added into a claimed unique-test total. The
backend skip needs a local RTDB emulator; no emulator port was opened.
The broad matrix includes all 24 cards, 1000 stress state variants per card,
V223-V225 adversarial checks, chess/AI, local clocks, online recovery, DM
acknowledgement, account erasure/isolation, player-state ordering and economic
request-recovery tests. It is not exhaustive proof of every possible state.

Visual inspection covered 31 menu screens in both languages at 390x844 and
their captured scrolled tails. Tutorial tests additionally cover 320x568,
390x844 with 1.8 text scaling and 768x1024. Menu data/HTTP are fixtures, not
live Firebase responses. Not every modal at every viewport was rendered.
Audio, haptics, frame pacing and thermal behavior were not heard/measured on
a phone. Existing VFX/motion regression tests are not a substitute for that.

## 5. Android Artifacts And 16 KB

Both local QA release builds succeeded using the existing signing setup:

- APK: build/app/outputs/flutter-apk/app-release.apk
- AAB: build/app/outputs/bundle/release/app-release.aab
- Identity: com.luno.chess, version 1.6.3, versionCode 18.
- minSdk 24; targetSdk 36; non-debuggable; not testOnly; cleartext disabled.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| APK | 175304967 | E8C2B6DA298C28BB2B1586410D34CD6454988F05C367873A8324FFC605808AB3 |
| AAB | 172291721 | DA0EB6B53773E29189798DC78A9FF63568C542C0567290D53B5E66C8B5CE156A |

- APK signature verification passed; its public certificate matches the
  pre-build signing evidence. AAB verification checked 1176 payload entries
  against the configured upload certificate.
- Every packaged arm64-v8a/x86_64 library passed the existing corrected V221
  ELF validator: 8 libraries in the APK and the same 8 in the AAB.
- APK zipalign -c -P 16 -v 4 passed. AAB declares PAGE_ALIGNMENT_16K and
  uncompressed native libraries. No ELF binary patching or RELRO disabling.
- The validator uses the pinned AOSP whole-LOAD/RELRO handling documented in
  native-package-audit.json, not the old V220 blanket modulo assertion.
- All 742 packaged original game assets match source in each artifact; all
  eight packaged 64-bit native payloads also match across APK and AAB.
- Runtime/assets remain byte-identical to the package build freeze. Only the
  screenshot test helper changed afterward; final-evidence.json also checks
  added/deleted source files and rehashes both packages.

ELF alignment, APK ZIP alignment, bundle configuration and testing in an
actual 16 KB environment are separate gates. These packages passed the first
three; the last remains unverified. See the
[official Android page-size guidance](https://developer.android.com/guide/practices/page-sizes).

Build 18 is a local QA identity, NOT a claim that Google Play will accept that
versionCode again. Check the last uploaded code and rebuild with an approved,
unused higher code before publication. No signing identity change is needed.

## 6. Remaining Conditions

1. Install from a Play testing track on a real Android phone and test clean
   install, loading, offline tutorial, AI match and re-entry after process death.
2. Test two real accounts through authenticated matchmaking, accepted moves,
   card targeting/resolution, reconnect, background/foreground and result
   settlement. Production App Check/Play Integrity was not exercised here.
3. Verify the current live backend contains the intended source changes.
   Previous V234 backend fixes were not deployed by this pass; source tests
   do not prove live server parity. No deploy is authorized in this request.
4. Run on an actual 16 KB environment and inspect Play's generated APKs and
   Pre-launch Report. No Android device/emulator runtime was available here.
5. Measure a prolonged match for FPS/RAM/temperature and verify audible card
   effects, music, haptics, keyboard and system insets on phone/tablet.
6. Confirm Play versionCode availability, signing/install path and billing
   behavior on the actual test track. Sideloading an upload-key APK is not
   proof of Play Integrity recognition or compatibility with Play app signing.
7. The build warned that Firebase plugins still apply the Kotlin Gradle
   Plugin. Builds passed, but this needs a planned toolchain/plugin migration
   before a future Flutter version makes it an error; no speculative upgrade
   was made in this pass.

No additional reproducible source defect remains open among the scenarios
covered by this pass. That statement is deliberately narrower than claiming
the entire product has zero bugs or is already proven production-ready.

## 7. Acceptance Summary

| Gate | Decision |
| --- | --- |
| Targeted source fixes / regression matrix | PASS after final evidence reconciliation |
| Tutorial local functional/layout acceptance | PASS within stated fixture/device limits |
| Android build, signatures and static 16 KB checks | PASS |
| Live two-player / production security acceptance | NOT VERIFIED |
| Physical-device / 16 KB runtime / Play acceptance | NOT VERIFIED |
| Production Android release | RELEASE HOLD |

The next step is the bounded device/Play/live acceptance list above, not an
unsupported zero-bug guarantee or another arbitrary readiness percentage.
