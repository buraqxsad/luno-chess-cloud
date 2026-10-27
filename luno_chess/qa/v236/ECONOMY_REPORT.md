# V236 Economy: Reconciled Evidence

Reconciled on 2026-10-26. Primary account/economy audit:
[backend-handoff.md](backend-handoff.md), dated 2026-10-22. Later execution
evidence is reconciled below instead of copying its earlier NOT RUN labels.
This sidecar performed read-only source/log/JSON and selected SHA-256 checks;
no SDK, test runner, server, emulator, Play request, purchase, deployment or
live-player operation was run. Prices, rewards and source were not edited.

Root: `C:\Users\Casper\Documents\Luno Chess\luno-chess-src\luno_chess`.
This is a local source contract audit, not deployed-backend equality or Play
Console acceptance. The main owner produces final source/artifact and online
reports. See [TEST_REPORT.md](TEST_REPORT.md) for execution provenance.

## Catalog Reconciliation

Compared active native sources ([shop](../../lib/screens/shop_screen.dart),
[cosmetics](../../lib/services/cosmetic_catalog.dart),
[Pass](../../lib/data/pass.dart), [chest contract](../../lib/services/chest_odds_contract.dart),
[billing IDs](../../lib/services/luno_billing_models.dart)) with backend
[catalogs.js](../../../functions/lib/catalogs.js),
[pass.js](../../../functions/lib/pass.js),
[chests.js](../../../functions/lib/chests.js) and fulfillment in
[index.js](../../../functions/index.js). The handoff found no discrepancy in
these inspected active offers; selected backend source hashes still match the
V236 source lock at this reconciliation. This is not an all-route live audit.

| Active offer | Client / backend source value | Result |
| --- | --- | --- |
| Common / rare / legendary chest | 500 / 1500 / 3500 gold | Match |
| Royal chest | 380 gems | Match |
| Common / rare / legendary / mythic emote | 500 / 1500 / 4000 / 10000 gold; 14 IDs | Match |
| Ottoman complete piece set | 1000 gold | Match |
| Roma / Brit / Viking / Tasdevri / Samuray complete set | 480 gems each | Match |
| Ice / Dragon complete set | 720 gems each | Match |
| Neon complete set | 980 gems | Match |
| Season Pass | 450 gems, 30 levels, 250 XP per level | Match; distinct from membership |

Backend soft-item catalog: **68 definitions** = 1 Pass + 9 piece sets + 14
emotes + 7 skins + 8 frames + 5 biography frames + 23 individual costumes + 1
costume pack. Chests and real-money billing products are separate catalogs.
Not all auxiliary/legacy definitions are visible native storefront offers.

Additional unchanged backend prices, retained for an accurate catalog record:

- Skins: obsidian 2000 gold; jade/ruby/sapphire 6000 gold each; amethyst/dragon 350 gems each; celestial 900 gems.
- Frames: bronze/silver/gold/royal 500/1500/5000/25000 gold; arena/mythic/inferno/frost 50/150/400/350 gems.
- Biography frames: emerald/ruby/ocean 3000 gold; royal/inferno 120 gems.
- Costumes, gems: k_crystal/k_commander 280, k_wizard/k_gold 480; q_crystal/q_shadow 280, q_gold 480; r_stone/r_royal 240, r_ice/r_mech 400; b_wizard/b_emerald 220, b_shadow/b_sun 360; n_armor/n_shadow 220, n_gold/n_dragon 360; p_soldier/p_archer 160, p_apprentice/p_gold 300. All-costume pack: 900 gems.
- Legacy upgrade definitions for trap/radar/resist/shield/deploy: levels 2/3 cost 2500/5000 gold with their existing arena gates. These are not the 24-card Battle V1 mana/power catalog and are not evidence of competitive card upgrades in that ruleset.

## Pass Accounting And Existing Rights

Currency totals from the source reward tables, excluding chest contents and
cosmetic duplicate compensation:

| Version / earned track | Gold | Gems |
| --- | ---: | ---: |
| V1 or V2 free | 12300 | 120 |
| V1 additional premium | 13950 | 540 |
| V2 additional premium | 13950 | 330 |
| V2 both tracks, gross | 26250 | 450 |

The premium-specific V2 gem return is **330**, not 450. Against the 450-gem
purchase, its incremental gem difference is **-120**. The free 120 is available
without buying premium. Both tracks return 450 gross gems only after all
levels/rewards are earned and claimed; this is not immediate reimbursement or
a claim that every player completes the Pass.

`LAST_LEGACY_PASS_SEASON=6`; source schedules fresh s7 V2 for 2026-10-28 UTC.
Explicit reward versions and existing unversioned earned/purchased rights
remain protected by the current version logic. This describes source behavior,
not the observed live season. Native previews honor server `rewardVersion`
and default legacy snapshots to V1. No old season entitlement was reduced.

Free content: laugh at 4, rare chest at 8, trophy at 12, legendary chest at 16,
Ottoman at 20, heart at 24, royal chest at 28, Viking at 30.
Premium content: rare chest at 5, angry at 10, Roma at 15, legendary chest at
20, Dragon at 25, Neon at 30.

Roma/Dragon/Neon standalone prices sum to 2180 gems, but require levels 15/25/30
(3750/6250/7500 XP from level 0). This is conditional cosmetic value, not liquid
currency. Already-owned sets compensate **1000 gold**, already-owned emotes
**250 gold**, not their shop price. Earned chests add pending inventory units;
duplicate pending units are preserved. Membership does not include season Pass.

## Chests: Gates, Ownership And Delivery

The handoff's rerun of
[v220-billing-odds-contract.test.js](../../../functions/test/v220-billing-odds-contract.test.js)
passed four tests. That file is also represented in the later full backend log.
These compare contracts/fixtures/algorithm hashes and ownership-dependent
availability, not measured production randomness or real-device consent.

Probabilities below are decimals for **independent category gates**, not a
mutually exclusive rarity distribution or fixed final per-item odds. Skin and
emote categories roll separately at the shown gates.

| Chest | Guaranteed gold | Skin / emote gates, each category | Frame / biography gate |
| --- | --- | --- | --- |
| Common | 50-150 | common 0.50 (1-3), rare 0.08 (1) | 0.05 / 0.04 |
| Rare | 150-400 | common 0.40 (1-3), rare 0.40 (1-2), legendary 0.08 (1) | 0.15 / 0.12 |
| Legendary | 400-1000 | common 0.30 (2-4), rare 0.50 (1-3), legendary 0.40 (1-2), mythic 0.05 (1) | 0.35 / 0.25 |
| Royal | 1000-2500 | rare 0.70 (2-4), legendary 0.80 (1-3), mythic 0.30 (1-2) | 0.55 / 0.40 |

Owned/completed cosmetic targets leave the eligible pool; rewards cap at the
remaining requirement. A frame gate gives two shards with probability 0.30,
otherwise one; a biography gate gives one. Common/rare frame/biography pools
use legendary rarity; legendary/royal also include mythic.

If regular rolls produce no cosmetic reward, fallback selects a remaining
eligible target. Its activation and final item odds depend on ownership; no
fixed universal fallback probability is asserted here. A complete collection
blocks a new paid chest. An already-earned Pass chest can still deliver only
guaranteed gold. No new competitive Battle V1 card is randomly rolled; legacy
card receipts remain recoverable. Catalog `items: 5/6/7/8` is metadata, not a
fixed count of delivered results in this algorithm.

Inspected native purchase flow refreshes owner state, checks price/currency,
availability and gold bounds against the odds contract, then requests odds
confirmation. Server entropy and durable paid/earned receipt replay remain in
place. Mocked repeated/lost-response tests do not prove live exactly-once
delivery under every outage.

## Confirmed Recovery Defect And Later Closure

`BE236-01` / `BE-01`, [economy.js](../../../functions/lib/economy.js): with a
retained deterministic ledger entry but missing top-level claim/purchase
marker, a retry could credit/debit again. Malformed proof normalization could
erase evidence. Fix rejects malformed containers/markers and orphaned ledger
evidence before mutation; valid legacy first grants and valid replay remain
supported. No silent repair, proof TTL or balance migration was added.

This was fault-injected partial-state recovery, not a demonstrated client
ability to edit server balances. Losing every durable proof cannot be inferred
from the remaining state. Corrupt profiles may need verified operator
reconciliation; rejection is not automatic successful recovery.

Earlier worker evidence: 3 pass / 9 fail before fixes across the new economy
and index files, then 12/0; combined light final selection 16/0/0 skip. Those
checks overlap the later full suite and are not extra passes to add.

The handoff originally marked three route cases NOT RUN. That is superseded
by [backend-regression.txt](backend-regression.txt), TAP cases **1264-1266**:
orphan onboarding credit rejected, missing daily cursor/claim rejected without
mutation, valid onboarding delivery survives request-cache loss. All passed.
The ten helper cases are TAP 1254-1263. The notification `fromUid` static index
fix is also tested, but is not a second economy defect or proof of deployment.

Full backend result: **1267 pass / 0 fail / 1 skip**. Skipped isolated RTDB
integration means local mocks/static assertions are not Firebase rule execution
or production transaction acceptance.

## Google Play Products And Remaining Gates

All 10 native IDs/types match the inspected backend fulfillment catalog:

| Exact product ID | Source grant / type |
| --- | --- |
| `luno_gold_1000`, `luno_gold_5500`, `luno_gold_15000` | 1000 / 5500 / 15000 gold; consumable |
| `luno_gem_80`, `luno_gem_500`, `luno_gem_1500` | 80 / 500 / 1500 gems; consumable |
| `luno_bundle_starter` | 2500 gold + 100 gems; repeatable consumable |
| `luno_bundle_pro` | 12000 gold + 500 gems; repeatable consumable |
| `luno_premium_month`, `luno_premium_year` | Membership until verified provider expiry |

[Google Play adapter](../../lib/services/luno_google_play_billing_adapter.dart)
uses provider `ProductDetails.price` for localized display. Missing products
are unavailable/disabled; no TL or regional price is inferred from source.
31/366-day metadata does not override verified subscription expiry.

Inspected source binds product/token to account identity, reserves token
ownership, persists the grant before consume/ack, rejects cross-owner/retired/
voided claims and requires durable ownership on completed/consumed replay.
Refund handling reverses once, recovers available balances and retains debt or
review for the remainder. These are source/mock-test observations, not a new
real-provider transaction certification.

| Acceptance area | Status | Boundary |
| --- | --- | --- |
| Local catalog, Pass and chest contract / recovery regression | PASS, scoped | Source and retained automated evidence only |
| Deployed source equality, real Firebase transactions/rules | BLOCKED | No live comparison; isolated RTDB integration skipped |
| Regional products/offers/prices and license test accounts | NOT RUN | No Play Console/provider access used |
| Real pending/cancel/failure/restore, consume/ack retries, RTDN | NOT RUN | Mocks are not provider acceptance |
| Subscription renewal/expiry/replacement, refund and account switch on devices | NOT RUN | No license-test device flow |
| Multi-quantity and partial-quantity refunds | NOT RUN | Not established by inspected evidence |

No price/reward/balance recommendation was applied. Human value, completion
rates and real-player balance remain unmeasured. Billing/device/Play acceptance
is still required. **RELEASE HOLD**; no readiness score or zero-defect promise.
