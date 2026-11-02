# Final source — four-case local Billing SDK proof

**PASS.** Captured commit `9d41c5055006907ee2dafdf8e5daf70bb9f2c7a3`, index SHA-256 `5c6800410e05ff020a8e576b67b2419eaad5f56f44a912d8d48ceace7c85b486`. This is a scoped local SDK/data result, not production Firebase/Auth/AppCheck/Play acceptance.

The earlier three-case baseline under `../sdk-proof/` remains unchanged. Repeated cases overlap and must not be added as seven independent tests. Earlier two incomplete attempts remain under `/workspace/luno-review/system-bug-hunt/economy/sdk-proof/`.

The final run waits for root backend and Dart/TypeScript differential completion. It first requires a three-second seed/read smoke, then runs exactly four cases with actual Firebase Admin SDK/RTDB transactions and independent-connection durable verification:

1. Confirmed pre-grant refund blocks a suspended currency grant.
2. ON_HOLD fences a suspended profile grant.
3. ON_HOLD fences a suspended granted-claim write.
4. A subscription is first granted through the actual fulfillment entry point; a subsequent owned verification sees fresh ON_HOLD without RTDN, returns purchase-not-active409, commits inactive claim/profile0 and equal revision/fence, and preserves unrelated gold.

Google provider responses are fake; no memoryDatabase fixture is used. Only a single exact-loopback proxy-selection condition in the actual bundled standalone transport is compiled differently in memory. Disk SDK/repo files, headers, proxy environment, all data/transaction code and server responses are unchanged. `standalone-transport.patch`, `transport-provenance.json` and `transport-audit.json` retain this limitation explicitly; unmodified-transport acceptance is not claimed.

Observed counts: `{'tests': 4, 'pass': 4, 'fail': 0, 'skipped': 0, 'cancelled': 0}`. Durable observations: `4`. Total elapsed: `14.081` seconds; combined Java+Node peak RSS `345236`KiB. SDK disk hash reverified: `True`. Port19000 closed: `True`; private logs remaining `0`.

Results/data are in `results.json` and `observations.json`; filtered logs in `fixed.log`/`emulator.log`. No Android runtime, physical performance or16KB test was run. The historical native raster SIGSEGV remains unresolved; RELEASE HOLD and real-service gates remain separate.
