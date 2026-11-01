# Independent subscription fence review

Read-only source review; no tests, emulator, deploy, code edits or commits performed by this reviewer.

Reviewed at 2026-10-30T22:31:17.702171+00:00.
Base HEAD: `96126331b7d38c2a06545a50924da0e5ea8e02b1`.
Initial reviewed `functions/index.js` SHA-256: `656c8e9c0bf5828f310e3fb39137e878d6be5f260f475410792d53c69d5384be`.
Initial production diff SHA-256: `20c6b7afafc68eb95fa0147356ae38438c15102dc9d9d0f37933f714270b613d`.

Initial status was PENDING FINAL DIFF. The final disposition below supersedes those pending findings. This review is not a full backend, Firebase or Play acceptance.

- Claim ownership/product/retired checks remain before mutation. A first global claim is still created only after verified provider ownership, avoiding unverified token reservation.
- Existing legacy revision-zero claims now pass `allowCreate=false`: authoritative disappearance cannot recreate them, while a cold null cache probe can retry against existing server data. This closes the earlier review finding.
- Granted, completed and failure-metadata claim writes carry an expected revision. Stale failure cleanup cannot change a newer lifecycle's metadata.
- A newer reconciliation stores a token-specific claim revision in the profile even when Premium was already zero and no local token receipt exists. The user transaction rejects an older verified grant.
- A more recent valid provider proof can advance an on-hold legacy token; there is no permanent subscription tombstone preventing renewal.
- Deletion checks and metadata anonymization remain around the transaction workflows. The retained claim cannot later be used as raw ownership authority.
- Subscription-state conflicts use HTTP503. The existing billing backend maps HTTP500+ to retryable queued behavior; no new wire field is required by the client.

## Boundaries awaiting the final patch

1. Completion currently performs a final claims-to-profile projection and then unconditionally returns `entitlementGranted:true`. A newer ON_HOLD reconciliation can win during that projection. Final admission must verify the purchased token's current owner/product/revision/active/expiry, not only aggregate `premium.active`: another valid token may keep aggregate access open while this token is held.
2. `Object.assign(oldMarkers, claimRevisions)` can lower an existing profile token marker if a claim snapshot has a lower revision. Preserve monotonic fencing or reject/re-read the stale snapshot. Marker retention itself must never be treated as grant authority.

The first point was sent to both parent and finishing agent with the additional other-token control. The finishing agent owns the final production/test changes. Exact final source hash and disposition will be appended after final-diff review.

## Final disposition

**No remaining source-review blocker identified within the reviewed subscription coordination scope.** The earlier pending findings and the introduced final-read boundary are addressed in the final source:

1. Subscription projection now precedes the final `status:complete` claim transaction. The granted token must be active, unexpired, and covered by the projected expiry; the final compare-and-set uses that token's exact expected revision. Another active token cannot authorize success for a newer held target token.
2. The profile transaction rejects/re-reads claim snapshots whose revision is below an already installed token fence **before** applying Premium or marker changes. Keeping a high marker while applying stale active access is not used.
3. There is no separate plain final claim read. The final completion CAS and `writeAccountMetadata` before/after deletion checks provide the commit boundary. Newer lifecycle changes before that CAS reject the old operation; changes committed afterward are later operations, rather than an impossible promise of perpetual activity.
4. Cold null probes, existing revision-zero claim disappearance, unverified-token ownership, valid on-hold recovery, stale failure cleanup, late acknowledgement and account retirement retain their protections. Full-profile revocation assertions remain exact; provider/query count expectations changed only for the documented additional revalidation/projection.

The reviewer inspected the 20-case adversarial source, including other-active-token control, final-CAS hold/erasure, stale marker plus Premium0, publication gap, and positive legacy recovery. Test execution belongs to the finishing agent and parent; this reviewer did not rerun or independently certify their TAP results.

Final source reviewed at 2026-10-30T22:36:48.368822+00:00.
`functions/index.js` SHA-256: `5b0a8ef98fd05ee3d8414db884b617fdef44881c2c3c27ade8be5fbaa82aaf59`.
Production diff SHA-256 at review: `c74f91dfc6600928028bb1df63a4812a026fa952a3b6906dc8a8215a64cf4a82`.

Real Firebase/App Check, licensed Play Billing, staging/production and native Android acceptance remain outside this review; no release PASS is implied.

Final adversarial test source SHA-256: `af6527eea53b73798f9814e0bf8e0d20171a05b8d9bd519b1eec0e5af71e80da`. Parent requested finalization against this exact source; no test/production files were changed by the reviewer.
