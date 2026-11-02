# Round 4 — Flutter account and persistence audit

**One new P2 preservation fault was proved and fixed.** The exact-baseline replay passed 15 controls and failed 20 cases; the final focused run passed **119/119**, with zero failed or skipped. The 20 baseline failures are boundaries within one fault family, not separate defects. Baseline: `d67cd449cbd8834a4878f5484941d376fa7c17d8`.

## R4-CLIENT-01 — rejected recovery writes become false success on retry

SharedPreferences updates its in-process cache before the platform acknowledges a write. `bindAccount` previously used `containsKey` as evidence that the unowned backup, backup owner, or damaged-account recovery copy was already durable. After a false or throwing platform write, a second attempt could skip that preservation step and finish binding. Leaving the restored account then replaced its original damaged archive without any durable recovery copy. First association could likewise complete without its recovery backup or ownership metadata; later authoritative erasure could not identify the orphaned backup.

`recovery-before.log` reproduces the fault using the actual SharedPreferences implementation and a platform transport double. The double records durable map contents separately from the plugin cache. Both malformed JSON and wrong-owner archives are rejected; false and throwing preservation writes are tested separately. The ordinary preservation controls pass. Persistent rejection proves the second switch unexpectedly succeeds, despite continued storage rejection.

This differs from round 3's accepted-edit-during-an-archive-await fault: here a failed write is mistaken for an existing durable copy on a later attempt. The existing round 3 stabilizing archive loop is retained.

## Correction and own-fix review

Production changes are limited to `luno_chess/lib/models/game_store.dart`:

- Unacknowledged damaged-archive recovery keys remain retryable even when the optimistic cache contains them.
- An acknowledged pending marker precedes a newly created unowned backup. The marker and in-memory attempt flag retain that unfinished departure through same-process retries and process restart, including failed correction writes and retargeting to another UID.
- After the bound owner snapshot is saved, pending-marker cleanup is best-effort. False/throwing/lost-response removal keeps an explicit retry flag; subsequent flushes retry once. Preference acquisition is guarded so lifecycle flush gains no new uncaught storage error.
- Completed pre-existing recovery copies remain untouched. Pending metadata is included in authoritative owner erasure cleanup; a failed first-UID association cannot delete the second UID's completed recovery or replace its restored account archive.

The final test file contains 49 cases. New-metadata implementation checks are excluded from canonical baseline comparison by name; the remaining 35 cases test behavior that already existed at baseline. Restart tests dispose the store and reset the SharedPreferences singleton without flushing first. False, throw-before-commit, and commit-then-throw outcomes are distinct. Marker removal tests also cover lost responses, bounded retries, and eventual cleanup.

## Verification status

- `recovery-before.log`: 4 pass / 9 fail, exit 1, original 13-case baseline proof.
- `recovery-after.log`: 83 pass / 0 fail, first 13-case fix plus 70 unchanged regressions.
- `recovery-expanded-intermediate.log`: 19 pass / 2 fail; retained own-fix expansion exposed missing durable restart intent.
- `recovery-final-candidate.log`: 105 pass / 0 fail, before the final no-throw cleanup/acquisition adjustment and additional UID controls.
- `canonical-before.log`: **15 pass / 20 fail**, exit 1, 35 cases against exact baseline GameStore bytes. `canonical-before-source-hashes.txt` records the baseline production hash and frozen test hash. Fourteen tests specific to the newly introduced pending metadata are excluded by `^(?!.*(backup_pending_v1|pending-marker)).*$`; they are own-fix checks rather than independent baseline defects. One missing-backup boundary surfaces as a null-to-String cast because the expected durable backup is absent; the durable-map absence is also directly asserted in the earlier fault cases.
- `root-final-focused.log`: **119 pass / 0 fail / 0 skipped**, exit 0: all 49 new cases and 70 unchanged regressions across six files. Counts overlap with the earlier runs and are not added together. This is the authoritative final source result.
- This agent's reviewed local-IPC command was not executed because automatic approval review hit its usage limit. That was an approval-service failure, not a determination that the action was unsafe. The parent subsequently submitted its own normally reviewed local validation request; it succeeded and ran the canonical replay and final regression. No approval bypass was used.

Final frozen source SHA-256:

- GameStore: `02c9d56f9a968741844e057ed220a59c8f62db2797d64a61229d4a67e141f371`
- New test: `558e01063ec708aee80db6154d73a8e227c2db4e5a13ba63044e1c8e9d055132`

Formatting and `git diff --check` passed. The production patch is `game-store-fix.patch`. `replay-baseline.sh` takes the shared Flutter lock, replaces only the owned GameStore file with exact baseline bytes, and restores the final file with an EXIT trap. The rejected agent command never ran that script and never mutated source. The parent's accepted execution restored the final GameStore hash, verified in `fixed-restored-source-hashes.txt` and rechecked after final validation.

Source review also inspected account bootstrap/recovery, same-UID epochs, deck read/save cache revisions, social read/stream ownership, profile navigation, and queued local writes. No additional independently proved defect is claimed. Billing, battle, tutorial, telemetry, settings and audio were outside this agent's ownership.

No full suite, analyzer, build, emulator, live-service operation, deploy, payment, upload, push, commit, signing change, asset edit or golden replacement was performed by this agent. Controlled platform storage/auth/HTTP checks do not establish production or native-device acceptance.
