# Round 5 client findings and correction

Current-source baseline: `6467e72f6181efc10420a98df1b7d7977cdf757a`.
The parent authorized the minimal production correction after reviewing failing
current-source proof and the external proposal. Only the billing service changed.
The nine-case current-source test is
`luno_chess/test/round5_client_billing_recovery_test.dart`.

## New P2 candidate: catalog failure cannot recover via app retry paths

When Play availability succeeds but its initial product query fails transiently,
`_available` remains true, the purchase stream remains subscribed, and the catalog
is empty. A later `start()` sees an apparently initialized native store and never
queries products again. The shop's visible retry calls `restore()`, which also
never queries products; it emits idle after state refresh, hiding the retry action.
All currency and membership offers remain unavailable for that account session,
even once the store query can succeed. The native service reports ready but no
localized purchasable products are loaded. A process/account restart or otherwise
unused direct `queryProducts()` API is required to recover.

Two current-source cases fail independently for start and the exact restore API
used by the shop retry. Healthy repeated start is a passing control.

## Prior-family coverage gap: stale pending ownership snapshot

A Play ownership query starts, a live purchase stream completes verification and
state refresh for a consumable, then the old ownership snapshot returns pending.
The product's verified status becomes pending, preventing the next purchase.
Both same-token and empty-token pending query entries reproduce this. A separate
await-boundary case proves it when receipt verification began before the query
and completed while that query waited. This is a
coverage gap in the prior canceled-pending/restore ordering family, not a newly
counted independent defect family. Current genuinely pending ownership remains
locked; completed receipt verification remains enabled.

## Evidence and limitations

- `billing-current-source.log`: initial invocation blocked by sandbox localhost
  socket restriction; zero executed behavioral cases. No approval bypass.
- `billing-current-source-ipc.log`: normal reviewed localhost permission approved;
  original 4-case proof: 1 pass / 3 fail, exit 1.
- `billing-expanded-before.log`: intermediate eight-case proof: 4 pass / 4 fail, exit 1.
- `billing-canonical-before.log`: final nine-case proof: **4 pass / 5 fail**,
  exit 1. Counts overlap and must not be added.
- `baseline-source-hashes.json`: exact current production and expanded test hashes.
- `billing-recovery-proposal.patch`: external correction proposal, now applied
  with parent authorization. `billing-final.patch` is the exact production diff.
  Empty catalogs are retried on start and restore. Catalog failure cannot block
  receipt recovery; failed catalog retry retains a retry status. Per-product
  status generations prevent old pending ownership observations from replacing
  live stream decisions.

- `billing-focused-after.log`: **75 pass / 0 fail / 0 skip**, exit 0. All nine
  new cases and 66 unchanged cases across seven files: core billing, explicit
  restore, historical receipt launch guards, round 2 state ordering, round 3
  pending reconciliation, and billing backend owner/retry boundaries.
- `billing-analysis.log`: targeted Dart analysis of production and new regression
  files completed with no issues (exit 0).
- `final-source-hashes.json`: exact final billing source, regression test, and
  unchanged GameStore SHA-256 values. Production diff: 36 insertions/4 deletions;
  unrelated formatter-only changes are absent. `git diff --check` passes.

GameStore journal cache behavior was inspected only and is not claimed as a
second independently validated defect. No journal production patch was made.
Controlled billing ports/backend responses are not Play, production payment or
native device acceptance.
No build, emulator, network service, payment, deploy, golden update or commit ran.
