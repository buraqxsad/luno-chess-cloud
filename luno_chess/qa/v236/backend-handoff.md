# V236 Backend Security And Economy Handoff

Date: 2026-10-22. Worker scope: `functions/lib/*`, new V236 backend tests, and
concrete production-rule/index defects. Main owns auth/client integration.

## Result And Boundaries

- Two narrow source defects addressed: one partial-receipt recovery integrity
  defect (P1, fault-injection condition), one missing static query index (P2).
- No new remotely exploitable P0 was reproduced. No new DM authorization bypass
  or client/backend price discrepancy was found in the inspected active paths.
- `functions/index.js`, battle rule core, Flutter production code, prices,
  rewards, assets, iOS and signing were not edited.
- No server/emulator, network/admin operation, deployment, purchase, account
  deletion, live configuration update or APK/AAB build was performed.
- All dirty/untracked V219-V235 work was retained. This is not a repository-wide
  release acceptance. **RELEASE HOLD** remains appropriate pending main regression
  and real Firebase/Play/device acceptance.

## Baseline

Actual roots: backend `luno-chess-src/functions`; Flutter sibling
`luno-chess-src/luno_chess`. No applicable `AGENTS.md` was found in the ancestor
locations or these source subtrees. The full attached request was read, with
sections 10/11 re-read separately.

Nested repo HEAD: `9e0ab47f913a5a20146a4c64e5858b5dd77bf304`. Flutter source:
`1.6.3+18`; backend package metadata: `1.5.7`, Node engine 22. These metadata
versions describe different components, not a newly diagnosed protocol mismatch.
Backend and production rules are untracked in this checkout; HEAD alone does
not identify their current content. Reviewed prior V220 backend/billing, V233,
V234 and V235 report evidence as historical context, not fresh test results.

## Confirmed Findings

### BE236-01: Partial receipt loss could replay a committed economy operation

File/functions: `functions/lib/economy.js`, `ensureEconomy`,
`applyRewardClaim`, `applySoftPurchase`.

Independent reproducer: perform a legitimate 500-gold reward or 1000-gold soft
purchase, remove only its top-level claim/purchase marker, retain its original
deterministic ledger entry, and retry. The old helper treated the missing marker
as a fresh operation, credited/debited again and overwrote the prior ledger.
Malformed scalar markers also fell through. Normalization replaced malformed
proof containers with empty objects, discarding evidence before deciding.

Fix: validate proof-container shape before normalization, reject malformed
existing markers, and reject a fresh grant/debit when its deterministic ledger
entry already exists. Preserve evidence for reconciliation; do not reconstruct
success, replay the grant, silently repair balances, or prune proofs. Valid
receipt replay and first grants on legacy profiles with absent containers still
work. Ledger lookups are constant-time; no whole-ledger scan was introduced.

Evidence: `v236-economy-evidence.test.js` had 8 failing negative cases before the
fix, then all 10 cases passed. Its expected behavior is no mutation/delivery on
ambiguous evidence, not a copy of a production amount calculation. Tests assert
the full profile remains unchanged on rejection.

Risk classification: this is fault-injected partial/corrupt-state recovery,
not evidence that a client can write server economy state or that these records
have been damaged in production. Existing permanent-item, Pass and chest route
validators already cover many purchase cases; this closes the shared helper
gap, not a newly demonstrated storefront exploit. Existing record-shaped legacy
receipts remain no-regrant markers; exhaustive historical receipt reconstruction
is not attempted. If every durable proof is removed, this change cannot infer
the lost history. No TTL/migration was added.

Remaining acceptance: the authored route tests below are NOT RUN here. An
ambiguous profile now fails closed with a TypeError (normally an API error),
not an automatic repair or a special new HTTP conflict code. Persistently
malformed profiles can require verified operator reconciliation; no live
profiles were read or changed.

### BE236-02: Notification sender cleanup query lacked its index

Source query: `functions/index.js`, `cleanupDeletedSocialPair`, uses
`notifications/<uid>.orderByChild('fromUid').equalTo(targetUid).get()`.
`firebase.json` actually selects `database.rules.production.json`, whose
`notifications/$uid` had no `fromUid` index.

Fix: add only `.indexOn: ["fromUid"]` under that existing owner node. Read/write
rules and every battle rule remain unchanged. Static regression failed before
the addition and passed after. This proves the source/config mismatch and its
repair; no current Firebase SDK/emulator/production query execution was run, so
no newly measured HTTP failure or deployment success is claimed.

## Actual Catalog Comparison

Current native sources inspected: `lib/screens/shop_screen.dart`,
`lib/services/cosmetic_catalog.dart`, `lib/data/pass.dart`,
`lib/services/chest_odds.dart`, `lib/services/chest_odds_contract.dart`,
`lib/services/luno_billing_models.dart`, Google Play adapter/service. Compared
with current `functions/lib/catalogs.js`, `lib/pass.js`, `lib/chests.js`, and
the billing/fulfillment code in `functions/index.js`.

| Active product | Native client | Backend | Result |
| --- | --- | --- | --- |
| Common / rare / legendary chest | 500 / 1500 / 3500 gold | Same | Match |
| Royal chest | 380 gems | Same | Match |
| Emotes, common / rare / legendary / mythic | 500 / 1500 / 4000 / 10000 gold | Same rarity prices, 14 IDs | Match |
| Ottoman piece set | 1000 gold | Same | Match |
| Roma / brit / viking / tasdevri / samuray | 480 gems each | Same | Match |
| Ice / dragon piece set | 720 gems each | Same | Match |
| Neon piece set | 980 gems | Same | Match |
| Season Pass | 450 gems, 30 levels, 250 XP/level | Same | Match |

The complete soft backend catalog has 68 items: 1 Pass, 9 piece sets, 14 emotes,
7 skins, 8 frames, 5 biography frames, 23 individual costumes, 1 costume pack.
The active native storefront principally exposes complete sets/emotes/Pass;
do not equate all legacy/auxiliary server definitions with visible native offers.
Additional exact backend prices, unchanged:

- Skins: obsidian 2000 gold; jade/ruby/sapphire 6000 gold each;
  amethyst/dragon 350 gems each; celestial 900 gems.
- Frames: bronze 500, silver 1500, gold 5000, royal 25000 gold;
  arena 50, mythic 150, inferno 400, frost 350 gems.
- Bio frames: emerald/ruby/ocean 3000 gold; royal/inferno 120 gems.
- Costumes (gems): k_crystal/k_commander 280, k_wizard/k_gold 480;
  q_crystal/q_shadow 280, q_gold 480; r_stone/r_royal 240, r_ice/r_mech 400;
  b_wizard/b_emerald 220, b_shadow/b_sun 360; n_armor/n_shadow 220,
  n_gold/n_dragon 360; p_soldier/p_archer 160, p_apprentice/p_gold 300.
  All-costume pack: 900 gems.
- Legacy upgrade definitions: trap/radar/resist/shield/deploy levels 2/3 cost
  2500/5000 gold, with existing arena gates. These are not the canonical 24-card
  Battle V1 power/cost catalog and were not changed or rebalanced.

### Pass Free Versus Incremental Premium

Fresh calculation from actual exported backend rewards:

| Version / track | Gold | Gems |
| --- | ---: | ---: |
| V1 or V2 free | 12300 | 120 |
| V1 premium additional track | 13950 | 540 |
| V2 premium additional track | 13950 | 330 |
| V2 both tracks, gross | 26250 | 450 |

The V2 premium-specific gem return is **330**, not 450. Against a 450-gem
purchase, premium's incremental currency difference is -120 gems; the free
120 gems are earned without premium. Both tracks together return the purchase
cost only if all 30 levels/rewards are earned and claimed. This is currency
accounting, not an assertion that the cosmetic/XP/time value is balanced.

`LAST_LEGACY_PASS_SEASON=6`; s6 on this audit date retains V1. Fresh s7 begins
2026-10-28 UTC with V2. Explicit versions and unversioned earned/purchased
entitlements are protected by the existing pass version logic. No old season
was reduced. Native `passPrem` respects server rewardVersion, defaulting legacy
snapshots to V1, and has matching per-level currency/content previews.

Free content: laugh at 4, rare chest at 8, trophy at 12, legendary chest at 16,
Ottoman at 20, heart at 24, royal chest at 28, Viking at 30.
Premium content: rare chest at 5, angry at 10, Roma at 15, legendary chest at 20,
Dragon at 25, Neon at 30. Roma/Dragon/Neon standalone prices sum to 2180 gems,
but require levels 15/25/30 (3750/6250/7500 XP from level 0). That is not liquid
gem reimbursement. Already-owned sets compensate 1000 gold and already-owned
emotes 250 gold under existing server delivery, not their standalone gem/gold
shop price. Chest rewards are additional pending inventory units, preserving
duplicates. Membership and season Pass are separate products.

### Chest Gates And Fallbacks

The existing four-test `v220-billing-odds-contract.test.js` was actually rerun:
all current chest/pool JSON, algorithm hash, shard gates, cap/fallback fixtures
and availability comparisons pass. This is source/fixture evidence, not a
measured production RNG distribution or a real device odds-dialog run.

| Chest | Guaranteed gold | Skin/emote gates, each category | Frame / bio gate |
| --- | --- | --- | --- |
| Common | 50-150 | common 50% (1-3), rare 8% (1) | 5% / 4% |
| Rare | 150-400 | common 40% (1-3), rare 40% (1-2), legendary 8% (1) | 15% / 12% |
| Legendary | 400-1000 | common 30% (2-4), rare 50% (1-3), legendary 40% (1-2), mythic 5% (1) | 35% / 25% |
| Royal | 1000-2500 | rare 70% (2-4), legendary 80% (1-3), mythic 30% (1-2) | 55% / 40% |

These are independent category gates, not mutually exclusive rarity odds or
per-item final probabilities. Owned/completed cosmetics leave the candidate
pool; each category selects among remaining eligible IDs. Frame roll gives
2 shards with 30% probability, otherwise 1; biography roll gives 1. Common/rare
frame/bio pools use legendary rarity; legendary/royal also include mythic.

When all regular cosmetic rolls yield nothing, choose one remaining eligible
cosmetic target as a fallback. Under the fresh-account fixture (classic skin,
smile emote owned), computed fallback activation is approximately 19.297920%,
8.205069%, 1.940262%, 0.047628% for common/rare/legendary/royal. These values
change with ownership and are not fixed advertised per-item odds. One remaining
target is eventually guaranteed; delivered pieces cap at that target's remaining
requirement. A complete collection blocks a paid chest, while an already-earned
Pass chest may still deliver only its guaranteed gold. No new competitive card
is randomly rolled; historical card receipts remain deliverable. Catalog
`items: 5/6/7/8` is metadata, not the actual fixed result count of this algorithm.

Before sale, native shop fetches fresh owner state, compares price/currency/
availability/gold bounds to the odds contract, and requests odds confirmation.
Server entropy and durable paid/earned chest replay checks remain intact.

### Google Play Catalog And Receipt Review

All 10 native product IDs match backend IDs/types:

| IDs | Server grant |
| --- | --- |
| luno_gold_1000 / 5500 / 15000 | 1000 / 5500 / 15000 gold |
| luno_gem_80 / 500 / 1500 | 80 / 500 / 1500 gems |
| luno_bundle_starter | 2500 gold + 100 gems |
| luno_bundle_pro | 12000 gold + 500 gems |
| luno_premium_month / year | Membership until verified provider expiry |

The abbreviated ID rows share their shown prefix. Bundles are repeatable
consumables in source, not account-once offers. 31/366-day metadata does not
override provider expiry. The native adapter uses ProductDetails localizedPrice;
missing products are disabled and display Unavailable. No TL price was invented.

Existing source checks bind product/token to SHA256(uid), enforce purchased or
active-subscription state, reserve token ownership in purchaseClaims, persist
the player grant before consume/ack, reject cross-owner/retired/voided claims,
and require the owned durable grant for completed/consumed replays. Refunds
reverse once, recover available balances and retain debt/review for the rest.
V220 refund pagination and V217 consumed-token recovery remain present. No
concrete new receipt defect in those inspected index.js paths was reproduced.

Not verified: real regional offers/prices, Console status, licensing, real
pending/cancel/restore/refund/RTDN, consume/ack retries, subscription replacement,
multi-quantity or partial-quantity refunds. `billingHealth` presence checks are
not proof of these gates. Main must retain the previous external acceptance
restrictions; no real Play request was made.

## DM Privacy, Indexes And Capacity

- Current production rules use exact conversation membership plus existing
  caller profile, not substring matching of an old conversation key. DM writes,
  sender-binding metadata and purchase claims remain server-only. Root reads
  remain denied. The old permissive `database.rules.json` is not the file
  referenced by current `firebase.json`; it was not deployed or rewritten.
- Existing canonical pair/legacy collision checks, legal consent, block checks,
  account deletion gates, sender/request/text/recipient proof binding and stale
  read-cursor checks were inspected. No new bypass was reproduced. Static rule
  assertions are not equivalent to running Firebase security rules.
- `ownedDirectMessageConversations` still uses the V220 compatibility path:
  dynamic `members/<uid>` filtered `.once('value')`, not `.get()`. There is no
  scalable static per-UID .indexOn declaration to add for arbitrary UIDs.
  A fresh send with no proof still takes this discovery path; the SDK can
  download/filter the whole DM tree. Do not remove that legacy discovery step
  without a complete durable owner-index migration and proof-replay contract.
- Opening a conversation transacts its retained tree. The native one-shot and
  stream reads also read all `msgs` (no limit), then parse them. Conversation
  proofs, sender bindings, per-player economy ledger and request receipts grow
  with activity. No cap/TTL was added that would reopen old request IDs.
- Static queries for purchaseClaims/uid, accountLinkTickets/uid,
  moderationReports/reporterUid/targetUid, publicProfiles sorting/search,
  battleV1Ratings/rating and match status/settlementStatus already have indexes.
  Key/value queries use existing key/value indexing. Only the concrete
  notifications/fromUid omission was changed.
- Cost example from current `online_match_screen.dart` timers: 2-second view
  polling plus 10-second heartbeat is up to 36 calls/player-minute before
  emotes/retries/room traffic. Assumption: 1000 foreground players for 60 minutes,
  timers serviced without suppression -> 2160000 calls (1800000 view polls,
  360000 heartbeats). At an assumed 4 KiB view, view payload alone is
  7372800000 uncompressed bytes. This is arithmetic, not measured wire traffic,
  RAM, production latency, invoice or saturation. No transport rewrite was made.

## Actual Checks Run

No npm test/pretest, TypeScript build, full backend suite, Flutter suite, server
or emulator was run by this worker.

1. Node v24.15.0, 128 MiB old-space, only new pure economy/static-index files:
   before fix **3 pass / 9 fail**, after fix **12 pass / 0 fail**. Durations
   reported by runner: 176.7865 ms / 192.7562 ms (not process wall time).
2. Existing chest odds contract file alone: **4 pass / 0 fail**, 582.9144 ms.
3. Fresh final run with repo's Node v22.23.3, 128 MiB old-space,
   `--test-concurrency=1`, those three light files together:
   **16 pass / 0 fail / 0 skip**, 343.3809 ms.
4. `node --check functions/lib/economy.js` and
   `node --check functions/test/v236-economy-route-recovery.test.js`: exit 0.
5. Small read-only catalog arithmetic: V1/V2 totals, 68-item count and the
   ownership-dependent fallback figures above. No balance changes.

New route-recovery file: three authored cases, syntax checked, **NOT RUN**:
onboarding orphan-credit rejection, daily cursor+claim loss rejection, and
valid onboarding cache-loss replay. It uses the existing in-memory DB test
adapter, not a real backend or Firebase emulator.

## Exact Serial Commands For Main

Run only in a coordinated test slot. This is a bounded selected regression,
not a replacement for main's final suite. No npm pretest or build is implicit.
Node heap is capped; total process RSS is not capped by this flag.

```powershell
Set-Location -LiteralPath 'C:\Users\Casper\Documents\Luno Chess\luno-chess-src'
$node='C:\Users\Casper\Documents\Luno Chess\.tools\node22\node-v22.23.3-win-x64\node.exe'
$files=@(
  'v236-economy-evidence.test.js',
  'v236-query-index-contract.test.js',
  'v236-economy-route-recovery.test.js',
  'v220-billing-odds-contract.test.js',
  'core.test.js',
  'reward-boundaries.test.js',
  'v215-product-economy.test.js',
  'v219-sidecar-product-integrity.test.js',
  'soft-purchase-recovery.test.js',
  'pass-purchase-recovery.test.js',
  'shop-chest-recovery.test.js',
  'pass-chest-recovery.test.js',
  'v218-pass-chest-entropy.test.js',
  'v217-billing-recovery.test.js',
  'v220-billing-pagination.test.js',
  'v221-backend-restore-invariants.test.js',
  'dm-receipt-race.test.js',
  'v221-backend-dm-rejected-attempt.test.js',
  'v219-sidecar-social-integrity.test.js',
  'v220-rules-contract.test.js',
  'v234-player-state-ordering.test.js'
)
foreach($file in $files){
  & $node --max-old-space-size=192 --test --test-concurrency=1 "functions/test/$file"
  if($LASTEXITCODE -ne 0){throw "Stopped on $file (exit $LASTEXITCODE)"}
}
```

Actual rule-engine/index execution is NOT RUN. Only an explicitly approved,
isolated emulator slot may verify that later; do not run a deploy, use a live
project or launch a server from this handoff automatically. Main's final
Flutter catalog/Pass/billing/account regressions also remain required.

## Changed Paths And Integrity

Only these six paths belong to this worker:

1. `functions/lib/economy.js`
2. `database.rules.production.json` (only notification index)
3. `functions/test/v236-economy-evidence.test.js` (new)
4. `functions/test/v236-query-index-contract.test.js` (new)
5. `functions/test/v236-economy-route-recovery.test.js` (new, NOT RUN)
6. `luno_chess/qa/v236/backend-handoff.md` (this report)

SHA256 before -> after:

| Source | Before | After |
| --- | --- | --- |
| economy.js | 588A08562F0266713BDAD0C7041971193E6A271BED3EA1FDEDF42F6742AB0F6B | A60DDDB5F7658DAA4EFFC4439E52C8E0F97E5B21EA78602A7F103EDF43A043D5 |
| production rules | 15D07E42FFB39DFFA7C75EEA286964426F9AEE965C8014B8D4FE9AB29FC9BD3D | 167998D9A535E5A88876429B7DF030763E4E9C3B753FF9625F6EDFBC6B68552A |

Protected `functions/index.js` remained
`A41FA94DCD691FC00A2D3B8FADFFAF1F922EA4BE8E1E8550D7F1E2DCA5F62F8A`.
Unchanged chest algorithm source remained
`A270AB989326179227A048E0197B943C2167B3BCC3F0967E833C1944F2F55415`.
No commit/stage/reset was performed. These are selected-file observations, not
a whole dirty-tree source freeze or deployed-backend equality proof.
