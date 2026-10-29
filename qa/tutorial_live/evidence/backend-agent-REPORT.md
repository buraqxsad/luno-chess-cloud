# Backend bug hunt — Premium race

**1 P1 production defect reproduced and fixed.** A suspended claim snapshot could overwrite a newly committed subscription's `premiumUntil` to zero. The inverse stale active snapshot could restore membership after another notification revoked it.

The new deterministic regression first failed against baseline source (`recompute-before-fix.log`, expected future expiry, actual 0). `functions/index.js` now captures the existing player revision before the claims query and checks it in the player transaction. A changed profile causes a fresh claims query, up to three attempts. Exhaustion throws retriable503 before committing or publishing stale membership. Existing purchase-claim authority, refund/revocation semantics, tombstones, Pass ownership and catalogs are preserved. No profile-receipt fallback or fake grant was introduced.

`functions/test/subscription-reconciliation-race.test.js`: **12/12 PASS**. Covers claim-snapshot vs fulfillment race; purchase-before-refresh cold/warm; old-token revocation vs new-token fulfillment; delayed active snapshot after revocation; legacy active claim without a profile receipt; inactive/retired claims despite stale active receipt; real-style repeated transaction callback; retry exhaustion with no stale profile/publication writes.

Focused existing suites plus the new file: **187 pass / 0 fail / 0 skip** across seven files, run separately with `node test/<suite>.test.js`. Exact per-file results in `focused-results.json`. Node syntax and diff checks passed. No full suite, emulator, live Firebase, payment, deploy, push or commit performed by this agent. Real Firebase/Play acceptance remains NOT RUN.

## RTDN retry after exhaustion

Two additional adversarial tests call the actual exported `playBillingNotifications.run(event)` handler for grant and revoke. Each event hits three-attempt profile contention twice, after its provider claim has already been persisted. Both deliveries throw503 and persist event status `failed` (attempts1 then2), leaving the original profile/publication unchanged. Replaying the **same event ID** with contention removed performs reconciliation, fixes membership and marks `complete` (attempt3). Only the fourth completed duplicate is suppressed. There is no claim-level notification dedupe gate that bypasses recomputation in the current source. No additional production change was required.
