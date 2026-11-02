# Round 2 — Flutter client bug audit

**Two new P2 defects were reproduced and fixed.** The earlier seven fixes were preserved and not recounted. The user's request for a “no bugs” result was not treated as an expected test outcome.

| New defect | Valid before-fix evidence | Fix and final coverage |
| --- | --- | --- |
| Billing refresh completion rolls back authoritative membership | `billing-snapshot-expanded-before.log`:2 pass /7 fail. Restore's old inactive snapshot can arrive after receipt verification's newer active snapshot. The service then permits an annual Play launch despite the newer monthly ownership; the inverse also blocks a legitimate renewal. | `luno_billing_service.dart` checks the same revision/observation ordering as GameStore before updating its own snapshot and ownership cache.12 new cases cover both directions, same-revision observation, old backend response, valid newer response, legacy-only backend, invalid version metadata and new-owner reset. |
| Delayed friendly join replaces a different top route | `friendly-route-before.log`:1 pass /1 fail. The real FriendlyOnlineScreen and LunoOnlineService with a controlled HTTP response replaced an unrelated MaterialPageRoute, while the current-route control worked. | `friendly_online_screen.dart` admits only current/resumed presentation. An accepted match stays pending while covered/paused and replaces the Friendly route once it is visible again; no unrelated route is replaced.5 new cases include normal, covered/return, pause/resume and stale covered/disposed callbacks. |

The final combined run passed **90/90**,0 skipped, across9 files (`client-final.log`, exit0). It includes17 new cases and73 existing billing/matchmaking cases. Prior intermediate runs overlap and are not added to that count. Production changes are limited to the two files above; the two new tests are `round2_client_billing_snapshot_order_test.dart` and `round2_client_friendly_route_test.dart`.

Exact commands used the pinned toolchain and the shared Flutter lock:

```bash
flock /workspace/luno-review/bug-audit-round2/flutter.lock bash -c 'source /workspace/toolchains/luno-env.sh; cd /workspace/luno-chess/luno_chess; flutter test --no-pub --concurrency=1 test/round2_client_friendly_route_test.dart test/round2_client_billing_snapshot_order_test.dart test/rc_matchmaking_owner_test.dart test/luno_billing_service_test.dart test/billing_historical_receipt_launch_test.dart test/luno_online_billing_backend_test.dart test/luno_google_play_billing_adapter_test.dart test/v220_billing_restore_test.dart test/v220_billing_pending_chest_recovery_test.dart'
```

`result.json` records exact baseline/fixed source hashes. `client-fixes.patch.gz` (decompress before applying) contains the production diff. No existing assertion, golden, rule, asset or signing identity was weakened or changed. The first Friendly harness attempts had missing localization delegates or an assertion inside the mock callback; they did not establish the navigation defect and are explicitly excluded. A later extra pause/resume test initially used an invalid Flutter lifecycle transition; its failing log is retained separately. The valid route regression used a real delayed service response, checked dispatch outside the mock callback, and passed its current-route control before the covered-route failure was counted.

Source review also covered account/epoch gates in API and user-data reads, account-modal ownership, deck-load/save admission, and existing tutorial/mentor lifecycle code. No additional defect was proved in those inspected boundaries. This was a targeted client audit, not exhaustive proof that every client path is correct.

**Native Android, real Play Billing and production Firebase acceptance were not run.** The existing97 historical pixel mismatches, previous native raster crash and external release gates are not cleared by these local tests. Source/test edits are frozen for the parent's final analysis/regression. The agent did not commit, deploy, upload or start an emulator.
