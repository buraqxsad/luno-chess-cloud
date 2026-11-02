# Round 3 economy audit — two new bug families fixed

**1 P1 + 1 P2. Root integrated both fixes. No further confirmed new defect in this scanned scope.** This is focused evidence, not production billing or release acceptance.

## P1 — first consumable claim misses an acknowledged unmatched refund

An initial Google `PURCHASED` lookup can be suspended before the global token claim exists. A refund RTDN then goes through the real exported `playBillingNotifications.run` handler: it writes `billingSignals/unmatched/.../status=awaiting-client-claim` and commits `billingEvents/.../status=complete`. The original purchase resumes using the stale reply, grants 1000 gold (1250→2250), then consume fails because Google has refunded the token. Later verify rejects `purchase-not-complete`, and redelivery of the sole refund is skipped as a completed duplicate. The existing known-claim reversal marker cannot protect a claim which did not exist when the only notification was acknowledged.

The patch extends existing post-registration subscription revalidation to first consumable registration. Ownership and product proof still precede claim registration; the fresh provider lookup happens **after** registration, so any later RTDN sees the claim and can use the existing same-profile reversal fence. Consumed state is derived from this fresh reply. A new consumed-after-registration control proves an earlier unconsumed response cannot invent a grant without a durable receipt.

Final new backend suite has 8 cases. The exact initial `d627e06` index, loaded without editing repository production files, is **5 pass / 3 fail**. Candidate and root-integrated actual source are **8/8 pass**. Controls preserve wrong owner/product rejection, initial canceled purchase rejection, ordinary grant/consume/replay, and the existing post-registration refund fence. Cold and warm refund variants are one bug family; the consumed case is a control of the same registration fix.

Evidence: `unmatched-refund-exact-baseline-final.log`, `unmatched-refund-candidate-final8.log`, `actual-round3-economy-unmatched-refund.test.js.log`, `unmatched-refund.patch`. Exact source/test SHA-256 values are in `result.json`.

## P2 — canceled pending payment remains busy after successful restore

A Play pending receipt sets a persistent per-product `pending` status. If the payment is canceled outside the running app, a successful current ownership query returns no receipt, but restore leaves that old status untouched. Gold repurchase remains `billing-busy`; a monthly pending receipt blocks all membership purchases until the billing session restarts.

The patch snapshots each pending receipt generation before querying ownership. Only an older pending generation absent from a **successful** ownership result is released, and only when no current launch or queued verification owns the product. New stream pending receipts retain their generation and remain blocked.

Six new Flutter cases are **4 pass / 2 fail before**, **6/6 after**. Four controls preserve an actually owned pending payment, failed query, newer stream event during an old empty query, and still-open native launch. The installed `in_app_purchase_android 0.5.3` source confirms `queryPastPurchases` queries both `inapp` and `subs` then maps every purchase while preserving purchase state. Existing adapter tests also prove pending preservation; the adapter source rejects an ownership response with a non-null error. This does not claim a real Play query occurred.

Evidence: `pending-baseline-with-adapter.log`, `pending-actual-focused.log`, `pending-restore.patch`.

## Final focused checks

| Actual integrated source | Cases | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Backend: 9 files, direct sequential Node execution | 134 | 134 | 0 | 0 |
| Flutter: 6 billing/service/adapter/restore/snapshot files | 72 | 72 | 0 | 0 |

These groups overlap prior regression records and must not be summed with other root runs. New unique cases total 14 (8 backend + 6 Flutter). Backend actual TAP counts per file live in `actual-focused-results.json`; Flutter source/test hashes and file counts are in `result.json`.

An existing retained-record test originally expected one provider lookup for first fulfillment. The new ownership-registration recheck requires two. Root applied `retained-record-expectation.patch`, which explicitly asserts initial lookup count2 and unchanged count2 after completed replay; consume1, one currency grant, idempotency and complete receipt assertions remain. The old candidate 65/66 failure is retained, not hidden or counted as a production defect.

Initial missing-file and sandbox loopback-EPERM startup attempts executed no test assertions and are excluded. The successful Flutter runs used the shared lock, exact handoff toolchain, `--no-pub`, concurrency1 and per-command local networking permission. No golden/asset/original assertion was removed or weakened.

## Scope and limits

Inspected first/owned fulfillment, consume retry/lost response, refund, RTDN acknowledgment/redelivery, subscription lifecycle/restore, billing debt/net currency behavior, client launch/pending/retry queues and daily cursor/streak/replay boundaries. Prior refund-grant and subscription fixes were retained and retested, not recounted. The narrow daily ordering/acceptance suites pass; no new daily bug was confirmed. Scope stopped at the parent's freeze request.

Node uses real exported backend and onMessage code with a memory database and fake Google replies. Flutter uses fake Play/backend ports and a real adapter with fake SDK-facing objects. No new actual Firebase/Admin SDK or licensed Play proof, physical Android, live deploy, real payment, upload, push or signing change occurred. Production source was only patched by root; this agent wrote uniquely named tests and external candidate/patch/evidence files.
