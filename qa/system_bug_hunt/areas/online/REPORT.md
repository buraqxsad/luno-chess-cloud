# Online integrity bug hunt

**Two verified defects fixed: one P1, one P2. Eight new behavioral regressions; 74/74 focused tests pass, zero skipped.**

Base commit: `fc11b702876d0d5c181c545bf6e52319fdddc520`. No `functions/index.js` edits, commits, live Firebase deployment, payment, emulator or Play upload by this agent.

## P1 — V1 terminal result maintenance could starve later players

`functions/lib/battle-v1-recovery.js` used a rotating cursor for active matches, but always queried the first 80 pending settlements. A full page of deferred records therefore blocked every later terminal result indefinitely. Repro seeds 81 valid terminal server matches from the actual authority, delays reads only for the first 80, and invokes the actual exported `sweep()` twice. The healthy 81st match stays `pending` in baseline code instead of updating the two real fixture accounts.

Fix: independent `battleV1Maintenance/settlementCursor`, validated match ID, bounded `orderByChild('settlementStatus')` range, exclusive cursor progression and wrap retry. Existing active cursor path and format stay unchanged. `database.rules.production.json` already declares `matchSecretsV1/.indexOn: [status, settlementStatus]`; no index/rules change is needed for this fix.

`functions/test/system-hunt-online-settlement-fairness.test.js`: before **1 pass / 2 fail**, fixed **3 pass / 0 fail**. Checks full failing page of 80, the healthy 81st match, bounded queries, wrapping back after transient failures recover, once-only account settlement and a healthy short backlog.

## P2 — Expired ranked search created an unjoinable friendly room

`functions/lib/battle-v1-friendly.js` correctly allowed room creation after a ranked search lease expired, but retained that stale queue entry. Guest joining checked the host's queue entry without its expiry and rejected the successfully created room with `OPPONENT_BUSY`.

Fix: remove expired search leases inside the existing friendly-control transaction before checking room occupancy. Expiry is `>=120000ms`, matching the existing `<TTL` availability rule. Live queue entries and active match guards remain enforced.

`functions/test/system-hunt-online-expired-queue-room.test.js`: before **2 pass / 3 fail**, fixed **5 pass / 0 fail**. Actual API sequence: enqueue → advance clock → create room → guest joins. Covers expiry exactly at 120000ms, 120001ms and 600000ms; active host/guest searches still block room actions and are retained.

## Evidence and verification

`settlement-baseline-exact.log` and `expired-queue-baseline-exact.log` rerun the final unchanged test files against production adapters captured read-only from the exact base commit. `load-baseline.cjs` compiles only those two historical files at their original module filenames, leaving the shared working tree untouched. Corresponding original source files and SHA values are recorded alongside. Fixed final logs are `settlement-final.log` and `expired-queue-final.log`.

Initial `node --test` child wrapper and a first baseline extractor hit this sandbox's Node child-process EPERM restriction. Those are preserved as initial/invalid launch logs, excluded from all test counts. Direct `node test/file.js` invokes the same `node:test` cases and produced the real per-case TAP evidence. A subsequent filesystem-only baseline loader also produced the expected per-case failures. The queue test's missing-value assertion was corrected to the fixture's `undefined` convention before final exact-baseline rerun; no existing test assertion was changed or weakened.

Focused final runs in `result.json`: new 8, V201B friendly 3, V201B recovery 6, V201B authority 3, V201B rollout 6, legacy settlement recovery 19, V217 late-settlement recovery 1, V213 progression 18, settlement presence 8, query-index contract 2 = **74 pass / 0 fail / 0 skip**. Node syntax checks and diff whitespace check passed. Repeated diagnostic reruns are not added to these totals.

Also inspected V1 action version/id ownership, timeout-before-action, resign retry receipt, public/private publication monotonicity, deleted participant access, bot planner inputs, completed-result analysis gating, legacy heartbeat/reconnect and settlement-presence paths. Existing focused assertions passed; this is not proof that every permutation is defect-free.

These are deterministic local API/maintenance tests with an in-memory DB adapter and injected transient read failures. Production Firebase/Play, actual client-rules SDK integration, simultaneous physical devices and native Android acceptance remain **NOT RUN** for this agent. The parent will run final broader regressions on the integrated source.
