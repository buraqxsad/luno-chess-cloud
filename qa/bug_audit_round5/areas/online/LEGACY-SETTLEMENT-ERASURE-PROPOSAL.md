# Existing erasure family: terminal legacy friendly replay

Independent legal local request sequence, separate from security's invitation-delivery probe:

`createFriendlyRoom(owner) -> joinFriendlyRoom(peer) -> submitMatchAction(owner,resign) -> deleteAccount(owner)=200 -> heartbeatRankedMatch(peer)=200`.

Actual deletion first removes `matchHistory`, `rankedReplays`, `rankedMatchViews` and `rankedPlayers` for the deleted owner. The surviving peer's terminal heartbeat calls `settleRankedMatch` again, which recreates those erased account records from the retained canonical match. Unlike rated settlement, friendly settlement skips profile transactions, so an absent deleted profile cannot stop this replay. Current-source two-case test: 1 positive live lifecycle control passes; 1 post-deletion case fails. The exact actual request test is `functions/test/round5-online-legacy-settlement-erasure.test.js`; baseline log is `legacy-settlement-erasure-baseline.log`. An initial test draft used `resign` instead of the legacy protocol's actual `resignation` result reason; that harness-only failure is preserved in `legacy-settlement-erasure-initial-fixture.log` and is excluded from bug evidence.

This is another concrete residual path of account erasure, not an additional new family. No production patch applied.

Minimal robust proposal:

* A complete legacy settlement should return its existing canonical result immediately instead of reapplying publication. Existing audit tooling already treats missing projections on a complete marker as manual review; pending records remain retryable. This closes serial heartbeat/duplicate-action replays without removing the surviving peer's stored result.
* Also guard each participant's late match publication with the existing `writeAccountMetadata` lifecycle fence, suppressing only `account-deleted` / `account-deletion-in-progress` for that participant and preserving ordinary errors for retry. This is needed for a pending worker already held before deletion; a complete-marker early return alone cannot fence an invocation that captured `pending` earlier.
* Apply the same per-participant fence to `publishRankedMatch` because an in-flight ordinary gameplay publisher can also finish after erasure. The cleanup must remove only the match-specific erased view/history/replay/message leaves, and conditionally retire `rankedPlayers[uid]` only if it still references that match; do not delete a newer status or surviving peer data.
* Account receipt application should tolerate only a proven deleted lifecycle state, keeping non-deletion profile failures retryable. Normal deletion's own legacy match settlement should still complete the surviving peer and preserve shared canonical receipts.

Before assignment, expand the proof to an interrupted worker that captured pending state and is released after real deletion, plus retained peer/newer presence controls. Canonical legacy name retention is a broader pre-existing privacy path and is not silently claimed fixed by publication fencing.
