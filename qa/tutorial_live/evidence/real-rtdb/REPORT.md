# Real RTDB SDK proof — Premium race

**Current fixed source: 3/3 PASS. Historical baseline: all 3 expected failures reproduced.**

The proof ran the actual backend entry points (`fulfillPurchase`, `recomputePremiumFromClaims`, `reconcilePlayNotification`) against the cached local RTDB4.11.2 emulator and Firebase Admin SDK 14.2.0. There is no memoryDatabase fixture. The only suspended operation is delivery of an already-read, real claim-query snapshot. All reads, writes, cache probes and transaction callbacks execute through the actual SDK. A separately initialized SDK app verifies durable profile/claim values before and after releasing the snapshot. Google Play provider responses are mocked; no payment or production acceptance is implied.

| Real SDK scenario | Baseline9233864 | Fixd07e7b4 |
| --- | --- | --- |
| Held old claims → actual subscription fulfillment → refresh | FAIL: committed future Premium becomes0 | PASS: committed expiry preserved; fresh claim query |
| Old-token revocation held → separate new subscription fulfilled | FAIL: new Premium becomes0 | PASS: old claim revoked, new entitlement retained |
| Held active claims → completed revocation → old refresh | FAIL: old active expiry restored | PASS: membership remains revoked |

Source files were captured read-only from exact commits. Their only difference is `recomputePremiumFromClaims`, checked by comparing both surrounding source segments and recorded in `source.diff`/`source-provenance.json`. Both complete source SHA-256 values were rechecked. Source files in the working repository were not edited.

Only localhost `127.0.0.1:19000` was started, using isolated demo project/namespace `demo-luno-premium-race` / `demo-luno-premium-race-default-rtdb`. No Auth, Functions, Android emulator, CLI or UI process was started. The preserved production rules were loaded into this local namespace, but these privileged Admin SDK cases do **not** establish client-rules authorization acceptance.

Final valid run elapsed 36.843s; peak combined Java+Node RSS 351524KiB (343.3MiB), below the600MiB budget. Java used Xmx192MiB/SerialGC/two CPUs. Java/Node stopped afterward and port19000 is closed. All temporary private logs were sanitized and removed. Initial invalid startup argument was preserved in `invalid-startup-*`; it did not bind a server or count as a test run.

`results.json` contains exact per-case durable observations and test counts; `baseline.log` contains the three intended assertion failures, `fixed.log` the three passes. `premium-races.cjs` and `run-proof.py` reproduce the isolated proof. No production/staging Firebase, App Check, Google account, real Play billing, physical device or release acceptance was performed.
