# Identity/security hunt — presence erasure race

**1 verified P2 production rules defect fixed.** Existing V235–V240/tutorial-live fixes were not recounted.

`database.rules.production.json` allowed `presence/$uid` writes solely when `auth.uid === $uid`. An already authenticated client could recreate presence after account erasure, using a delayed heartbeat or `onDisconnect().set()` registered before deletion. Account deletion atomically removes both user and presence, but the old rules never required the profile to remain present. This affects user-linked presence metadata, not economy, another account or protected profile writes.

The minimal fix adds `root.child('users').child(auth.uid).exists()` to the active presence write condition. Existing ownership and online/timestamp validation stay unchanged. `firebase.json` selects this production file. Legacy `database.rules.json` has no presence grant and is not selected; it was not edited. This agent did not edit `functions/index.js`.

## Reproduction and regression

Real RTDB4.11.2 + Firebase Admin SDK14.2.0, `databaseAuthVariableOverride` client identities, isolated demo-luno-presence-erasure-default-rtdb, only 127.0.0.1:19000:

- Preserved baseline rules: **9 pass / 3 fail / 0 skip**. Reproduced unprovisioned UID write, deleted UID late write, and registered onDisconnect restoring erased presence. Persisted offline row: baseline-observations.json.
- Fixed rules: **12 pass / 0 fail / 0 skip**. Actual rules reject all three. Live owner write/heartbeat/remove and live-profile onDisconnect keep working.
- Wrong UID with its own live profile and null-auth connection are denied in both runs, proving client rules evaluation rather than privileged Admin bypass. Malformed flags, missing/future timestamp and old-UID writes after account switch remain denied.
- Static source contract, labeled separately: before2pass/1fail; after3/3pass.
- Eight focused suites run directly with `node test/<file>.test.js`: **113 pass / 0 fail / 0 skip**. Includes AppCheck ID, deletion gate, metadata erasure, V1 migration, social races and DM receipt races. Exact per-file counts: focused-direct-results.json. Contract is included, not added twice.

The runner run-presence-proof.py starts one bounded RTDB process, loads exact supplied rules and runs repository file functions/test/system-hunt-identity-presence.integration.js. Canonical baseline and fixed runs use the same integration file. An earlier external prototype differed only in module/output plumbing; canonical baseline supersedes it. Initial module-resolution startup failure remains in invalid-module-* and is excluded. Multi-file `node --test --test-concurrency=1` emitted only file-level passes; focused.log is preserved but not counted as113 assertions. Per-file direct TAP is authoritative.

```bash
source /workspace/toolchains/luno-env.sh
python3 /workspace/luno-review/system-bug-hunt/identity/run-presence-proof.py fixed /workspace/luno-chess/database.rules.production.json
cd /workspace/luno-chess/functions
node test/system-hunt-identity-presence.test.js
```

Against an already running isolated RTDB with rules loaded:

```bash
GCLOUD_PROJECT=demo-luno-presence-erasure FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:19000 node test/system-hunt-identity-presence.integration.js
```

The integration refuses other project/host and configured cloud credentials. No Auth/Functions/Android/UI service starts. Combined Java+Node peak233336KiB (227.9MiB); all processes stopped and port19000 closed. Authentication-bearing diagnostics were filtered.

## Legitimate bootstrap

Active Flutter sources have no presence/ writer or presence onDisconnect registration. Legacy startPresenceSystem runs only from activatePlayerUI(user,onlineReady) when onlineReady=true. finishAuthenticatedBoot waits for loadUserProfile and verifies _profileLoadedUid===user.uid first. bootstrapAuthenticatedPlayer first refreshes authoritative state or provisions a guest using secure createGuestPlayer username reservation. Offline guest passes onlineReady=false. Existing/Google account boot also requires the loaded profile. Requiring a persisted profile therefore preserves legitimate ordering. Live seeded-owner/onDisconnect controls also exercise amended rules. This is not a real Google login acceptance result.

Other reviewed areas: verified AppCheck identity/allowlist handler boundary, tombstone gates and late metadata cleanup, Google-link ownership, DM membership/collision defense, social pair deletion cleanup. No second independently reproduced defect was fixed in this scope. Full suite and production/staging Firebase/AppCheck/Google/Play/physical-device acceptance remain root release gates. No deploy, payment, upload or push.
