# V236 Production Online Wiring Audit

Audit date: 2026-10-26. Scope: current Flutter Android source in
`luno-chess-src/luno_chess`, sibling `functions`, selected Firebase configuration
and RTDB rules. Source-only sidecar; main owns package rebuilds and read-only live
probes. This file is the only sidecar-owned output so far.

## Early Handoff: Specific Actions

1. **OW-01, P1 Android-attestation policy gap, source confirmed:**
   `functions/index.js:326-344` accepts any successfully verified App Check token
   with a nonempty app ID. It does not compare that ID to the Android Firebase app
   configured in `android/app/google-services.json` (`client_info.mobilesdk_app_id`).
   `AUTH_FALLBACK_ROUTES` is empty (`functions/index.js:83`), and missing, invalid,
   expired and the custom emulator-only token are rejected in production. That
   is project-level attestation, not an Android-app allowlist. If Android-only
   production attestation is the requirement, add an explicit server-side
   allowlist after SDK verification, retain emulator behavior only in an explicit
   emulator environment, and add accepted-Android/rejected-other-app route tests.
   The decoded platform/build request body is client-supplied and cannot replace
   this check. No foreign-app token was obtained or used; this is not evidence
   of unauthenticated access or a bypass of receipt/authorization checks.
2. **Verify live rollout before claiming connected matchmaking:**
   `functions/lib/battle-v1-rollout.js:13-29` reads
   `battleRollout/config`. A missing node selects `LEGACY_ONLY`, which disables
   V1 matchmaking (`functions/rules-v1/src/online/protocol.ts:103-105`).
   Confirm the live validated config enables V1, is not in maintenance, and has
   an Android minimum build at or below the final installed build. Source build
   is currently `1.6.3+18` (`pubspec.yaml:19`); package metadata, not that source
   string, is sent at runtime. No live config was read or changed by this sidecar.
3. **Verify deployed backend and rules independently of AAB:**
   `firebase.json:3-8` selects sibling `functions`, its battle predeploy build,
   Node 22 and `database.rules.production.json`. V236 economy recovery and
   `notifications/$uid/fromUid` index fixes are present in source, but the prior
   handoff explicitly says they were not deployed. Main must establish current
   deployed equality or retain this gate as BLOCKED; a rebuilt AAB does not carry
   server code or deploy rules. Do not deploy the permissive legacy
   `database.rules.json`.
4. **Complete external Android identity/billing acceptance:**
   local Google config has one matching Android package, two Android OAuth
   certificate entries and one web OAuth client. This does not prove Play App
   Signing SHA-1/SHA-256 registration, provider enablement, Play Integrity/App
   Check setup, Publisher IAM, active products/base plans or RTDN delivery. Keep
   these as live/device gates, not source bugs or passed tests.

No production source edits, SDK/heavy suites, servers/emulators, live requests,
deployments, test accounts, purchases or player-data changes were performed.
No credentials, tokens, API keys, OAuth client ID values or signing material are
included. Existing dirty/untracked work was preserved.

## Current Source Identity

Backend-parent paths below are relative to `luno-chess-src`; `lib/`, `android/`
and `pubspec.yaml` denote its `luno_chess` child. No applicable `AGENTS.md` was
found in the checked ancestors or Flutter/backend source trees. The full request
attachment, current `FINDINGS.md` and `backend-handoff.md` were read. Outer and
nested Git status were inspected. Nested HEAD is
`9e0ab47f913a5a20146a4c64e5858b5dd77bf304`, but extensive existing modified and
untracked files mean HEAD is not a source identity or deployment identity.

### Android And Firebase

| Item | Current source evidence | Live verification |
| --- | --- | --- |
| Package | `android/app/build.gradle.kts:48,58`: namespace/application ID `com.luno.chess`; no applicationIdSuffix/flavor in this app file | Final AAB/Play-delivered package belongs to main; not inspected here |
| Native Firebase loading | Google Services plugin at `android/app/build.gradle.kts:6`; `Firebase.initializeApp()` at `lib/services/luno_online_service.dart:382` | No Android Firebase bootstrap executed |
| Firebase project | `.firebaserc:3`, `android/app/google-services.json:5`: `luno-chess` | Current project status/IAM not queried |
| Android Firebase app | `android/app/google-services.json:11-13`: `1:955253747543:android:136188eaab561c9b29d812`, matching package | Console registrations not queried |
| OAuth configuration shape | One matching Android client; two type-1 entries for the same package, one type-3 entry in `oauth_client`; native Google initialization at `lib/services/google_account_credentials.dart:15-26` | Certificate roles and Play App Signing correspondence not independently verified; no keystore read |
| Version/build | `pubspec.yaml:19`: `1.6.3+18`; installed versionCode is read through `MainActivity.kt:18-29`, validated by `lib/services/app_release_identity.dart:14-26`, inserted at `luno_online_service.dart:1657-1669` | Main must compare final artifact metadata and actual installed build |
| Signing guard | `android/app/build.gradle.kts:32-44,65-79` requires local release signing configuration; no debug-sign fallback is selected there | No signing operation or key/certificate validation performed here |
| Transport | `AndroidManifest.xml:2` has INTERNET; the native API and Firebase database URLs are HTTPS | Merged manifest/target SDK/network behavior are main's final package/device checks |

The native runtime URL is exactly
`https://europe-west1-luno-chess.cloudfunctions.net/lunoApi`
(`lib/services/luno_online_service.dart:220-221`). It matches function region
`europe-west1` (`functions/index.js:55`) and export `lunoApi` (`:4211`).
The Google config database URL (`android/app/google-services.json:4`) matches
the backend production database URL (`functions/index.js:50-54`):
`https://luno-chess-default-rtdb.firebaseio.com`.
No native `useAuthEmulator`, `useDatabaseEmulator`, alternate API URL or
environment-based production URL override was found in `lib/**/*.dart`.
Backend HTTP database access is guarded by `FIREBASE_DATABASE_EMULATOR_HOST`.
No `.env*` file was present at the inspected `functions` top level; this says
nothing about deployed environment variables or the runtime service account.

### Auth And Release Attestation

- Native release/profile selects `AndroidPlayIntegrityProvider`; debug selects
  `AndroidDebugProvider` (`luno_online_service.dart:2613-2627`). App Check is
  activated before anonymous/account bootstrap (`:380-406`). Token acquisition
  failure returns null (`:2630-2644`); the HTTP call may still be sent without the
  header (`:2509-2524`), but the current server rejects it. No offline grant or
  successful online readiness is manufactured by this failure path (`:413-443`).
- The shared handler verifies revoked Firebase ID tokens, App Check, and
  account-deletion eligibility before calling a route
  (`functions/index.js:264-269,4189-4198`). `AUTH_FALLBACK_ROUTES.size` is zero
  in current source. OPTIONS preflight is intentionally outside mutation auth.
- OW-01 was checked against the installed Admin dependency source without
  invoking it: `functions/node_modules/firebase-admin/lib/app-check/token-verifier.js:97-119`
  verifies project audience and a nonempty subject, not an application allowlist.
  Production `verifyAppAttestation` then accepts that ID. Existing tests at
  `functions/test/core.test.js:20-52` model arbitrary current/legacy verified app
  IDs and missing/invalid token rejection; they do not enforce an expected app ID.
  Those tests were read, not rerun. Suggested regression: valid expected Android
  app accepted; valid different same-project app rejected; malformed token,
  missing token and production emulator bypass rejected; representative economy
  and match routes cannot mutate after rejection.
- An app-ID allowlist does not by itself prove release provenance: console
  provider registration, signing SHA-256, verdict policy and registered debug
  tokens still require verification. Do not label this source gap a reproduced
  live Integrity bypass. If this shared API intentionally serves older apps,
  preserve explicitly approved clients with an explicit policy rather than
  silently breaking their account/economy access.
- Native Google acquisition requires a nonempty ID token
  (`google_account_credentials.dart:8-26`). Explicit restored-account sign-in
  uses `signInWithCredential`, selected-UID server refresh and ownership guards
  (`luno_online_service.dart:1254-1392`); linking is separate (`:1395` onward).
  Anonymous provider enablement, Google provider enablement, OAuth consent and
  reinstall/second-device restore remain NOT RUN here.

### Functions And Runtime Route Wiring

`functions/package.json:6-8` selects `index.js`, Node 22. The Firebase predeploy
hook builds `functions/rules-v1` (`firebase.json:4`), whose `build` is `tsc`
(`functions/rules-v1/package.json:8`) and output is `dist`
(`functions/rules-v1/tsconfig.json:6`). Active backend Battle V1 modules import
that generated directory (`functions/lib/battle-v1.js:4-6`). Do not substitute
an old `dist` upload or an AAB build for the backend predeploy build/equality
gate. No build or generated-output equivalence check was run here.

A bounded read-only source extraction compared literal `'/operation'` strings
in `lib/**/*.dart` with the base ROUTES object, explicit Battle V1 assignments,
registered route-name loops and product-telemetry routes. Result: **67 unique
client literal route names, 74 registered backend routes, 0 missing names**.
References: `functions/index.js:4151-4180,4246-4250` and
`functions/lib/product-telemetry.js:165`. This is static name coverage, not
payload-schema, reachability, handler execution or deployment acceptance.

Server-only names in that extraction are `billingHealth`, `cancelMatchInvite`,
`claimSocialVisitReward`, `getBattleV1Rollout`, `getPublicPlayerProfiles`,
`restorePurchases`, `setConversationMuted`. Their absence as client literals is
not automatically a defect. In particular, native restore queries owned Google
Play purchases and individually verifies receipts, rather than trusting the
aggregate legacy restore count (`lib/services/luno_billing_service.dart:276-285`).

Scheduled exports also need live equality/status checks:
`sweepRankedMatches`, `sweepBattleV1` (each every minute),
`sweepProductTelemetry` (daily), and Pub/Sub `playBillingNotifications`
(`functions/index.js:4212-4214,4252`). RTDN topic defaults to
`luno-play-billing-events`, overridable by `LUNO_BILLING_RTDN_TOPIC` (`:84`).
Source presence is not proof of Play Console topic configuration, Pub/Sub
publisher IAM, scheduler execution or successful event delivery.

### Selected Rules, Paths And Indexes

The selected rules parse as JSON and deny root reads/writes. There is no active
Firestore/storage rules target in this `firebase.json`; the inspected native
online paths use RTDB and the HTTP API. Direct native streams align with rules:

| Native read | Rule boundary |
| --- | --- |
| `matchInvites/$uid` (`luno_online_service.dart:1815-1817`) | Owner read, server-only write (`database.rules.production.json:201-205`) |
| `dmInbox/$uid` (`:1974`) | Owner read, server-only write (`:230-234`) |
| `dm/<sorted pair>/msgs` (`:2006-2011,2141-2151`) | Existing user and exact conversation membership (`:236-239`); no parent/root read granted |
| `friendRequests/$uid`, `notifications/$uid` (`:2166-2178`) | Owner read, server-only write (`:189-193,223-228`) |
| `.info/connected` (`:679`) | Connectivity signal only; not server API/auth/attestation readiness |

Battle publication splits `matchesV1/<id>/public` and per-UID private state;
participant/owner rules are at `database.rules.production.json:6-18`.
`matchSecretsV1` remains unreadable to clients (`:20`). HTTP participant checks
and public/private projection construction are at `functions/lib/battle-v1.js:18-35`
and `functions/rules-v1/src/online/protocol.ts:64-96`. Canonical action parsing
binds match ID, action ID, expected version and protocol (`protocol.ts:37-42`);
server authority handles commit and duplicate/version decisions
(`functions/lib/battle-v1.js:64-75`). No two-player or security-rules runtime test
was executed for these observations.

Structured index checks found no missing expected entry in these 10 groups:
`notifications/$uid: fromUid`; `purchaseClaims: uid`; `accountLinkTickets: uid`;
`moderationReports: reporterUid,targetUid,status`; `publicProfiles:
trophies,collectionScore,seasonScore,wins,username,playerCode`;
`battleV1Ratings: rating`; `matchSecretsV1: status,settlementStatus`;
`rankedState/matches: status,settlementStatus`; `usernames: .value`;
`playerCodes: .value`. Relevant queries include
`functions/index.js:693,948,1599-1616,2749,2834,2922,3944,4066-4092` and
`functions/lib/battle-v1-recovery.js:85-90`. These checks do not execute RTDB's
rules/query engine or confirm deployed indexes.

### DM, Economy And Billing Boundaries

- DM server routes retain current legal consent, block/friend-only checks,
  exact pair membership and legacy-key collision rejection
  (`functions/index.js:3470-3498,3547-3564`). Durable request proof binds sender,
  recipient, text and actual stored message; message, proof and inbox changes
  share a multipath update (`:3501-3545,3568-3578`). No new DM authorization
  bypass was demonstrated by this source audit.
- Existing capacity risks remain: new DM sends without proof can scan the
  dynamic unindexed `members/<uid>` discovery path
  (`functions/index.js:640-642,3518-3527`); opening transacts the retained
  conversation (`:3476`); native reads the entire `msgs` tree without a limit
  (`luno_online_service.dart:2006-2011,2141-2151`). Retained request/economy
  proofs grow. A durable owner-index migration and bounded history plan need
  replay/privacy tests; do not simply delete discovery or TTL old proofs.
  These are known source capacity risks, not new measured production failures.
- Economy mutation routes remain under the shared Auth/App Check handler and
  RTDB `users/$uid` writes remain denied (`database.rules.production.json:29-33`).
  V236 orphan-ledger/corrupt-proof recovery protection is still present; selected
  source hashes below match the prior backend handoff. This is not live equality.
- All 10 current native billing IDs and kinds match `PRODUCT_CATALOG`:
  six currency packs, two consumable bundles, two membership subscriptions
  (`lib/services/luno_billing_models.dart:6-17`, `functions/index.js:120-130`).
  No price or grant was changed. Soft-currency catalog audit is documented in
  `backend-handoff.md`; it was not re-executed as a suite here.
- Billing reuses the online API (`luno_online_billing_backend.dart:36-44,78-89`).
  The adapter uses Play ProductDetails prices, rejects absent/ambiguous offers,
  binds obfuscated account identity and disables client auto-consume
  (`luno_google_play_billing_adapter.dart:52-122,138-147`). Server uses runtime
  ADC/Publisher scope (`functions/index.js:3626-3629`), package-bound provider
  verification and hashed owner binding (`:3635-3666`), and server consume/ack
  (`:3821-3828`). No credential file is required to be embedded in the AAB.
  Publisher access and real purchase lifecycle remain unverified. `billingHealth`
  checks catalog presence only (`:3848-3871`), not active offers, purchase
  delivery, refunds or RTDN end-to-end behavior.

## Acceptance Handoff

| Gate | Source result | Fresh live/device result by this sidecar |
| --- | --- | --- |
| Package/project/database/API target consistency | PASS, static scope above | NOT RUN |
| Literal route registration and selected static indexes | PASS, bounded checks only | NOT RUN |
| Missing/invalid App Check fail-closed boundary | Configured in source | NOT RUN |
| Expected Android-app App Check identity | OW-01 policy gap; no allowlist | NOT RUN; triage/fix before claiming Android-only enforcement |
| Anonymous/Google Auth and cross-device restore | Native wiring configured | NOT RUN |
| V1 rollout/min-build/maintenance state | External RTDB config dependency | BLOCKED pending main's current read-only evidence |
| Deployed source/rules/schedules equality | Selected local files identified | BLOCKED pending main's current deployment evidence |
| Two-account match/reconnect/result/social privacy | Source routes and guards inspected | NOT RUN |
| App Check/Integrity on Play-delivered release | Release provider configured | NOT RUN |
| Play products/Publisher IAM/RTDN/real test receipts | Source configured; IDs/types match | NOT RUN |

Required evidence for main: current app registrations and Auth provider status;
App Check provider/allowed verdicts and RTDB enforcement status; approved debug
token policy; Play App Signing SHA-1/SHA-256 registration correspondence; current
validated `battleRollout/config`; deployed function region/runtime/revision,
selected rules equality and scheduler/RTDN wiring. Live reads alone cannot
replace the still-required actual Android/Google consent/two-account/Play test
purchase acceptance. Do not weaken fail-closed behavior to get an online demo.

**RELEASE HOLD for production-online acceptance** until the policy gap is
resolved or explicitly accepted with its intended client policy, and the
mandatory live/device gates have current evidence. This sidecar gives no
whole-product release decision, readiness percentage or blanket online claim.

## Evidence Integrity And Commands

Performed only read-only `git status --short`, `git rev-parse HEAD`, `rg` source
searches, bounded `Get-Content`, JSON `ConvertFrom-Json` checks, source-only route
and SKU name extraction, and `Get-FileHash -Algorithm SHA256`. One initial hash
collection command had a PowerShell foreach-pipeline syntax error; corrected
and rerun successfully. No source/runtime tests are claimed. New outputs were
written with `apply_patch` only: this report and `config-summary.json`.

Selected current hashes (full SHA-256 values and additional inputs are in the
sanitized JSON companion):

| Path | SHA-256 |
| --- | --- |
| `functions/index.js` | `A41FA94DCD691FC00A2D3B8FADFFAF1F922EA4BE8E1E8550D7F1E2DCA5F62F8A` |
| `functions/lib/economy.js` | `A60DDDB5F7658DAA4EFFC4439E52C8E0F97E5B21EA78602A7F103EDF43A043D5` |
| `database.rules.production.json` | `167998D9A535E5A88876429B7DF030763E4E9C3B753FF9625F6EDFBC6B68552A` |
| `lib/services/luno_online_service.dart` | `F58987F6E81798002654157669B5C23CCE84C550D895FD38DD0EF5886A9EF849` |

These are selected local source observations, not a freeze of the shared dirty
tree, generated output, final AAB or running backend. No source file was edited
by this sidecar.

Final output check: the companion JSON parsed successfully, all 13 recorded
input hashes still matched the source files, and neither output matched the
limited API-key/private-key/access-token/OAuth-client-ID/JWT patterns checked.
That pattern check is not a repository-wide secret audit. Existing report files
and all other workers' files were left untouched.
