# Round 3 — Flutter client audit

**Two new P2 defects were proved and fixed.** The final focused run passed **124/124**, zero failed or skipped, across nine files. Thirteen cases are new; 111 preserve existing persistence, account, bootstrap and refresh behavior. Runs overlap and their counts are not added together.

Baseline: `d627e06a963e6ab5f85d479ac53cbb161eb8ce3f`. Production changes are limited to `luno_chess/lib/models/game_store.dart` and `luno_chess/lib/services/luno_online_service.dart`. New tests are `round3_client_departure_write_test.dart` and `round3_client_bootstrap_continuation_test.dart`.

## R3-CLIENT-01 — departure archive loses an accepted local edit

`bindAccount` serializes a departing account's snapshot before awaiting its archive write. The old owner remains current during that await. A real `chooseUsername('latest_name')` call can therefore finish and persist the latest active snapshot while the older archive is stalled. On switching back, the stale archive restores `original_name`, losing an edit whose save already completed.

The original valid before run passed its ordinary switch control and failed the delayed-archive case: **1 pass / 1 fail** (`departure-before-valid.log`). Expanded exact-baseline coverage was **1 pass / 6 fail** (`departure-before-expanded-valid.log`). It also covers false/throw archive failures, edits during correction writes, bounded persistent churn, and preservation of the unowned recovery backup while restoring an existing account.

The fix finishes candidate parsing before changing owners, then checks that the departing archive still represents the live snapshot. It writes later accepted edits before the synchronous owner commit. Correction writes are bounded: sustained mutation or storage failure rejects the switch with the original owner, binding revision and live edits intact, and a later switch can retry. Existing queued saves, account erasure and archive validation remain covered by unchanged regression tests. This result concerns local persistence; it does not establish a server economy loss or a complete native account-switch journey.

## R3-CLIENT-02 — guest creation resumes under a later session

`_ensureRemoteProfile` performs lookup, guest creation, local username-draft persistence, then starts a new `refreshState`. It retained no ownership across that local await. The original first-UID creation flow could consequently start its final `getPlayerState` request under a second UID. Same-UID logout/login, bootstrap retry and local response-epoch rotation also admitted a fresh request from the stale continuation.

The expanded valid baseline passed the ordinary-session and dispose controls and failed four boundaries: **2 pass / 4 fail** (`bootstrap-before-six.log`). `bootstrap-before-expanded.log` shows the exact observed sequence: `getPlayerState(first)`, `createGuestPlayer(first)`, then **`getPlayerState(second)`**. The HTTP response and the local SharedPreferences write are controlled separately; the auth stream and normal service restart path perform the account transition.

The earlier `refreshState` fix validates completion of one read. This is a distinct enclosing-flow defect: after guest creation, it started a separate read without retaining its original owner. The fix captures owner, request generation and bound store epoch in `_ensureRemoteProfile`, and validates them before creation, after creation, and after local persistence before the final read. The prior refresh completion checks remain unchanged. No cross-account server data disclosure or production deadlock is claimed by these tests.

## Evidence and verification

`canonical-before.log` replays all thirteen new cases with **both affected production files at their exact frozen baseline bytes**: **3 pass / 10 fail**, exit 1. `canonical-before-source-hashes.txt` records those production and test hashes. The replay used the shared Flutter lock, restored both fixed files with an EXIT trap, and verified their hashes afterward. No other source files were changed for the replay.

`client-final.log` is the authoritative fixed result: **124 pass / 0 fail / 0 skipped**, exit 0. The exact command and per-file hashes are in `result.json`; `client-fixes.patch` contains the production diff. Final source hashes are:

- GameStore: `f5932f691465c57fee4ed124f4587d3ef13e9b2754e9ede8e45bcb35098cd79d`
- Online service: `09459e1f3eee4d516828b48d522b913acf71b0d297778b57a01a8f29917b4449`

The first unprivileged Flutter attempt failed to bind a loopback socket before any test ran. An intermediate test expansion was accidentally inserted inside its helper class; its compile-failure runs are retained and excluded. That harness error was corrected without changing existing assertions. The valid final combined run is separate. No test oracle, golden, asset, rule or signing identity was changed.

Source review also inspected API/read session fences, same-UID auth reentry, social request and stream ownership, account modal routing, public-profile loading, deck cache read/save revisions and local write/erasure queues. No further independently proved defect was found in those reviewed boundaries. This is a scoped audit, not proof that every client path is correct.

**No full suite, analyzer, build, emulator or real service acceptance was run by this agent.** Controlled HTTP/auth and SharedPreferences platform doubles do not establish production Firebase/Google/Play or physical-device acceptance. The historical visual failures, native crash and release gates remain open. No deploy, real payment, upload, push, commit or signing change was performed. Source and tests are frozen for the parent's final integration and regression.
