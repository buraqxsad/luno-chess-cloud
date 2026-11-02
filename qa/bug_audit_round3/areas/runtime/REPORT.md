# Final root integration — fixed P2

The cold-cache defect was fixed and committed in `000faaaada3106bc5bf306d02498821f046773e2`. The actual Friendly module still has SHA-256 `5a69e284206501df9feb93904de4e532ea6917f54aa2d8eac25105f94e90b7bb` on the final build source. The same four actual-SDK desired-behavior assertions passed **4/4**, with zero fail/skip, against a fresh capture of that fixed source. Cold existing data now retries and succeeds; genuinely missing data still404. The independent SDK verified that the declined invite and inbox notice were removed while unrelated data remained. `fixed-proof/results.json`, `fixed-proof/proof.log` and `fixed-proof/observations.json` preserve this second run separately from the failing baseline.

The focused repository regression covers both accept and decline plus cold/warm/missing states: exact baseline **6 pass /2 fail**, fixed **8/8 pass**. The new tests are `functions/test/round3-runtime-friendly-cold.test.js`. The fixture semantics were established by the actual SDK proof rather than invented as a complete oracle.

The agent’s final report turn ended at its usage limit after persisting the successful actual SDK and unit results. Root verified the saved evidence and exact source hash; earlier failures were preserved. No second confirmation run was needed. This does not validate production Auth/App Check/Firebase or native Android. The historical baseline report follows unchanged.

# Runtime round 3 — actual SDK cold-cache transaction bug

**One new confirmed source bug, P2; root's fix verified by the same four actual SDK assertions.** A newly initialized Admin SDK app rejected a valid existing Friendly invitation with `INVITE_UNAVAILABLE`404 when declining it. The SDK first calls the transaction callback with its local cache value `null`. The old generic Friendly transaction helper caught the missing-invite error and returned `undefined`, which aborted immediately and prevented the SDK from obtaining the actual remote root. This is distinguishable from a genuinely absent invitation. Fixed actual-SDK result: **4pass/0fail**; focused repo regression baseline6pass/2fail → fixed8pass/0fail. [Fixed-source evidence](fixed-proof/REPORT.md).

No repository production or test files were edited by this probe. The exact Friendly module was captured from baseline commit `d627e06a963e6ab5f85d479ac53cbb161eb8ce3f`, SHA-256 `24db67ece22b41a0f70a42c75aea612365564e86796aa21916910d915f99dd9a`, and compiled at its original module path. During the run, root's separate send-invite metadata change existed in the working source; the captured `transact` and `respondBattleV1Invite` scopes were checked byte-identical before and after. `source-target.json` records the observed HEAD, working file hash, and actual protocol/module dependency hashes.

## Actual run

Real Firebase Admin SDK14.2.0 and RTDB emulator4.11.2; independent named Admin app seeds and reads durable state. Each tested app is newly initialized. The cold tested app performs **zero reads before its actual transaction**. The exact captured Friendly module runs with ancillary admission, entry, player, social lock/permission/friendship and rate-limit dependencies stubbed. SDK data, callback retry, transaction and response behavior remain real.

| Case | Actual callback/data result | TAP |
| --- | --- | --- |
| Raw SDK cold-cache retry control | First callback `null` returns `null`; server CAS detects remote root, second callback sees existing invite and commits its removal | PASS |
| Captured Friendly cold existing valid invite decline | One callback `null`, returns `undefined`; handler throws404; independently read invitation and notification remain unchanged | **FAIL** against desired success assertion |
| Same fixture, warm root control | Held real SDK root value listener supplies existing invitation; decline succeeds and deletes both control invite and notification; unrelated data survives | PASS |
| Independently verified truly empty database | Cold callback `null`; correct `INVITE_UNAVAILABLE`404; durable database remains empty | PASS |

Actual TAP: **4 tests /3 pass /1 fail /0 skipped /0 cancelled**; worker exit1. This is an intentionally failing regression proof, not a passing suite. The runner exits0 only after verifying this exact expected count and four durable observations; it labels the outcome `CONFIRMED SOURCE BUG`.

Evidence: `proof.log`, `observations.json`, `results.json`, `captured-friendly.cjs`, and `cold-root.cjs`. One derived `root_unchanged` field initially used JSON string equality, which differed solely due to RTDB object-key ordering; it was recomputed using object equality over the same stored data and is true. The unchanged original artifact is `observations-original.json`; TAP and callback observations were not changed.

## Minimal candidate fix — report only

```diff
- async function transact(change){let error;const tx=await db.ref('battleV1Control').transaction(value=>{error=null;try{return change(state(value));}catch(e){error=e;return;}},undefined,false);if(!tx.committed){throw error||new BattleError('TEMPORARILY_UNAVAILABLE',503);}return tx.snapshot.val();}
+ async function transact(change){let error;const tx=await db.ref('battleV1Control').transaction(value=>{error=null;try{return change(state(value));}catch(e){error=e;return value===null?null:undefined;}},undefined,false);if(error||!tx.committed){throw error||new BattleError('TEMPORARILY_UNAVAILABLE',503);}return tx.snapshot.val();}
```

Returning `null` on a validation failure observed at local-null cache allows the actual SDK CAS retry. If the database is truly empty, the no-op null transaction can commit; checking the stored validation error even when `committed` is true preserves404 instead of claiming success. A retry with actual remote state clears the stale initial error. Root applied this fix with a source comment; this agent then verified the exact fixed source with the same four actual SDK assertions and added only the uniquely named focused regression requested by root. Generic-helper consequences beyond the demonstrated decline are source implications, not separately claimed actual-SDK executed cases; acceptance is additionally covered by the focused deterministic regression.

## Boundaries and cleanup

The prior harness's narrowly permitted transport adapter was reused: one proxy-selection condition in the actual bundled `@firebase/database-compat/standalone` module is changed **in memory only**, and only for exact `ws://127.0.0.1:19000/.ws` with namespace `demo-luno-cold-root-r3-default-rtdb`. All other socket destinations are rejected. Proxy environment, headers, SDK disk files, SDK database logic and responses stay unchanged. `transport-provenance.json` and `transport-audit.json` record hashes, five selected local connections, zero rejected other URLs, successful SDK seed/read smoke, and unchanged inherited proxy variables. Unmodified-transport acceptance is not claimed.

One emulator, Java Xmx192MiB; total10.644s; peak combined Java+Node RSS232604KiB (about227.2MiB), below600MiB. Full attempt bound37s plus bounded cleanup, below45s. Processes terminated; port19000 closed; private logs0. Rules loaded only on the local demo namespace with fixed local owner header; no credentials read or remote service accessed. Initial default sandbox denied socket creation before any emulator process was started; the actual run used per-command network permission. No emulator Android, Flutter, build, full suite, deploy, upload, signing, money or push action occurred. Native and production release gates remain separate.
