# Pure rule engine — fourth adversarial audit

**No new confirmed production bug found in this inspected scope.** No rules source, existing test assertion, contract, fixture or golden was changed. No new repository test was added without a discovered defect. All 30 owned source and contract files match baseline `d67cd449cbd8834a4878f5484941d376fa7c17d8`; hashes are in `source-provenance.json`. Other agents’ concurrent changes are outside this statement.

| Executed check | Actual result |
| --- | --- |
| TypeScript build | PASS, exit 0 |
| TypeScript identity-renaming invariant | 258 states, all 4,775 outgoing branches, 19,616 explicit assertions; PASS |
| TypeScript relative-turn invariant | 258 states, all 4,775 outgoing branches, 19,616 explicit assertions; PASS |
| Pure Dart identity-renaming invariant | 258 states, all 4,775 outgoing branches, 19,616 explicit assertions; PASS |
| Pure Dart relative-turn invariant | 258 states, all 4,775 outgoing branches, 19,616 explicit assertions; PASS |
| Existing `v219-rules-contract.test.js` direct Node execution | 60 pass / 0 fail / 0 skip |
| Existing `v223-terminal-cards.test.js` direct Node execution | 14 pass / 0 fail / 0 skip |

The new TypeScript probe is itself invoked directly with Node and reports actual TAP: 2 pass / 0 fail / 0 skip. Together with the two existing files, the direct Node total is 76 passed TAP cases. Dart executes two explicit invariant groups, separately from the Node cases. The new probes perform 78,464 counted assertions across the two implementations. Existing tests’ internal assertion totals were not instrumented; they are not invented or added to that figure. No initial failed run or incomplete probe is omitted.

The new checks differ from previous conservation, reflection, codec/perft and hidden-world probes:

- **Identity renaming.** Each fixture state receives bijective replacement names for active/captured referenced piece identities and effect identities. The transform also rewrites all identity references and the serialized public fingerprints in repetition history. Removal-card action targets are rewritten. After undoing that renaming, each complete authoritative transition must equal the original, including hidden hand/deck/knowledge, triggers, effect expiry, special authorization, terminal metadata and history. Complete legal action sets before and after every branch must correspond.
- **Relative turn translation.** Every side already beyond its first turn receives an additional 17 own turns, and each modifier deadline moves by the same side-specific amount. Initial first-turn counters remain fixed. The paired complete authoritative output and complete successor legal set must agree after undoing the translation. This actually changes 254 of 258 states; four unchanged first-turn states are counted transparently. This exercises cost/block/Echo/discount deadlines and next-turn scheduling across all 24 cards without choosing new card balance expectations.
- Both implementations verify retained original and transformed inputs after every branch. The Dart probe decodes the serialized source states, then derives and applies its own legal actions; it does not consume TypeScript expected outputs.

The bound is exact: 113 existing canonical fixture paths produce 258 states, comprising 148 card, 102 chess, four pending and four terminal states. Every outgoing legal action is checked: 1,383 moves, 2,825 card plays, 403 discards, 148 passes and 16 secret resolutions. All 24 cards have played branches. Eleven states hold movement-card authorizations spanning all five movement cards. `coverage.json` records the per-card branch counts. These same 4,775 branches are reused under each law and implementation; they are not distinct independent game scenarios to sum.

Source review includes the model/codecs, all 24 card transitions, special movement geometry and authorization, castling/EP/promotion identity movement, capture → entry → final-position trigger order, effect expiry, draw/knowledge updates and terminal/public repetition accounting. The existing focused files additionally assert published Mine/repetition and unresolved-secret/terminal-card behavior. The bounded new checks use exact representation and relative-time invariants, not an invented independent card oracle. No new order-independence or arbitrary-tree claim is made.

Pinned activation is `/workspace/toolchains/luno-env.sh`: Dart 3.13.1 and Node 22.23.3. Commands and raw per-file logs are retained. Pure Dart needs no Flutter test listener, so this agent did not start Flutter or contend for its shared lock. No full suite, emulator, native device, production service, payment, upload, deployment, signing or push was performed. No generated untracked `luno_chess/qa/` asset was created. The existing visual/native/real-service release gates remain open outside this scoped result; this is not whole-product release acceptance.
