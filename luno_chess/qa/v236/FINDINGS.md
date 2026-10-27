# V236 Concrete Findings

Current checkout: latest Flutter source after V235, `1.6.3+18`, protocol
`LUNO_BATTLE_V1`. Dirty/untracked source is identified by `source-lock.json`,
not by HEAD alone. No live deployment, purchase or user-data deletion occurred.

## Fixed Root Defects: 12

| ID | Severity | File / function | Reproduction and root cause | Fix and regression | Residual risk |
| --- | --- | --- | --- | --- | --- |
| AUTH-01 | P1 | `lib/services/luno_online_service.dart:signInGoogle`, `lib/models/game_store.dart:bindAccount`, Settings and username setup | A new install with an existing Google-linked account had only a link operation. A credential conflict did not provide a way to restore that account. Associating pre-bootstrap unowned local state with the selected account could also contaminate local progress. | Separate explicitly confirmed account restore, quarantined guest data, canonical selected-UID server refresh, owner/revision/request-generation guards; `v236_google_restore_test.dart`, `v236_account_restore_ui_test.dart`. Before-fix TR/EN missing-button failures preserved. | Actual Google consent/token exchange, signing-certificate OAuth configuration, and cross-device restoration still need Android/live acceptance. No account merge or purchase transfer is promised. |
| AUTH-02 | P1 | `lib/services/google_account_credentials.dart`, `linkGoogle`, account deletion reauthentication | Android Firebase plugin's generic provider path builds an OAuthProvider; it is not the documented native Google credential flow. Link/reauth used that generic path. | Native `google_sign_in` 7.2 credential acquisition, nonempty ID token requirement, `linkWithCredential`, `signInWithCredential`, `reauthenticateWithCredential`, no token persistence/logging. `v236_google_credentials_test.dart`, existing Google link/deletion suites. | Mocked credential tests do not prove production OAuth/App Check or Play signing acceptance. |
| HS-01 | P1 | `lib/screens/battle_v1_screen.dart`, `lib/battle_ui/hotseat_privacy.dart` | Hotseat viewer changed immediately after a move; the person still holding the phone could see the incoming hand/deck and access their semantics. | Initial/turn/rematch consent replaces the private subtree, with per-viewer epochs and stale callback rejection. Actual board taps and semantics/private-widget absence are covered by `v236_hotseat_screen_test.dart`. | Physical app-switcher snapshots, TalkBack and rapid real-device handover are not verified. |
| HS-02 | P1 | Same screen: lifecycle, private modal and pending-choice handling | Background/resume retained private modals, targeting and consent. Stale modal callbacks could outlive the visible player. | Revoke consent on non-resumed states, remove owned routes without reverse animation, clear presentation only, retain authoritative Prophecy/Fate transactions, require fresh consent before reopening. Clock continues; expired consent cannot recover time. | Process-death local-match restoration is not newly implemented. Actual lifecycle/audio timing remains a device gate. |
| DECK-01 | P1 | `lib/screens/battle_deck_screen.dart` exit handling | Edit a valid deck and use app/system back: unsaved draft was silently lost. | One account-scoped Save/Discard/Keep editing flow, invalid-draft reason, save/back deduplication and mounted/current-owner checks. `v236_deck_navigation_test.dart`. | Unsaved draft process-death persistence is not added; external account removal intentionally invalidates it. |
| DECK-02 | P1 | Same screen: save/reconcile | Server commits a deck but response is lost/malformed/timed out: editor said it was not saved without checking. | One bounded validated read, exact ordered-deck confirmation, honest unconfirmed state and read-only Check save. No automatic second write. Tests cover ambiguous write, failed read, rights change, owner changes and retry. | A read before a delayed server commit can still see old state; draft is retained and explicit recheck remains necessary. |
| DECK-03 | P2 | `lib/battle_v1/deck_metrics.dart` | Heavy warning used average >=3.5 although the exact maximum legal ten-unique-card average is 3.0. | Warning uses a strict majority of cards costing more than opening card-phase mana, complete decks only; separate affordability/conditions/removal indicators. Five independent metrics tests. | Metrics are guidance, not a human win-rate or balance guarantee. No card cost changed. |
| BE-01 | P1 | `functions/lib/economy.js:ensureEconomy/applyRewardClaim/applySoftPurchase` | Fault inject missing top-level receipt while preserving deterministic credit/debit ledger, then retry; old helper could commit again. Malformed proof containers could erase evidence during normalization. | Reject malformed proof containers/markers and orphaned deterministic ledger evidence before mutation. Preserve corrupt state for reconciliation. Eight red negative cases then focused regression; route tests in full backend suite. | This is partial-state fault injection, not a demonstrated remotely writable client exploit. Total loss of all proofs cannot be inferred. Corrupt profiles can require verified operator reconciliation. Not deployed. |
| BE-02 | P2 | `database.rules.production.json:notifications/$uid` | Account deletion cleanup queries by `fromUid`; selected production rules lacked its index. | Add only `.indexOn: ["fromUid"]`; no access grants changed. Static selected-config/query contract test. | Does not prove an executed production query failure or live rule deployment. Not deployed. |
| UI-01 | P1 | `lib/battle_ui/layout.dart` | Actual 320x568 Flutter capture measured board width 224 logical px, wasting portrait width and shrinking pieces/targets. Short/large-text coach area could also be hard-cropped. | Full portrait board width 304 logical px at 320; compact own HUD, pinned normal-battle board and scrollable lower controls; short/large-text learning content scrolls without clipping coach text. 30 battle + 30 tutorial cases, TR/EN x 5 sizes x 3 text scales. Before red width test and PNG preserved. | At small sizes/large text, lower controls require scrolling. This is not an all-controls-in-first-viewport claim. Device touch/FPS are separate. |
| UI-02 | P2 | `lib/app.dart:UsernameSetupScreen` | At 320x568 and 2x text, scalable `@  ` prefix plus large padding clipped the username hint. | Fixed-width 24 px familiar prefix icon and tighter horizontal padding, without clamping user text scaling. Before PNGs and 4 account UI cases. | Native keyboard/IME variation is not covered by widget rendering alone. |
| LICENSE-01 | P2 | `pubspec.yaml`, `lib/services/luno_font_licenses.dart`, `lib/main.dart`, Settings licenses action | Full Cinzel/Spectral notices were absent from delivered assets; existing Nunito OFL was not declared for delivery. Embedded license URLs alone were insufficient notice delivery. | Add two official full OFL texts, declare existing Nunito notice, lazy LicenseRegistry registration and offline Settings licenses route; `v236_font_licenses_test.dart`, actual packaged-asset check. Original font bytes unchanged. | Not a blanket legal certification. Complete original artwork/audio provenance remains unverified. |

## Improvements, Not Additional Bug Counts

- Training welcome now explicitly distinguishes its stopped clock from normal
  own-turn time, which continues during card selection.
- Deck guidance now separates opening affordability from legal target/condition
  availability. No balance, rewards, mana or ranking rules were changed.
- Current product AST inventory, asset metadata/font cmap/WAV audits and actual
  Flutter captures were refreshed. Static coverage is not a button-execution claim.

## Test-Harness Issues, Not Product Defects

Intermediate failures and their repairs are retained in the QA logs:
test locale/delegate setup; async fake assertions inside Flutter guard zones;
lazy-list target visibility; temporary spinner while confirmation is open;
semantics/timer disposal timing; and a fake `bindAccount` override needing the
new optional named argument. No production defect count includes these.
Legacy copy assertions were updated only for intentional unconfirmed-save copy;
the incomplete-deck metric assertion now checks the actual draft contract.
Behavior, write-count, account ownership and privacy expectations were retained.

46 legacy battle golden mismatches were expected from the inspected portrait
layout change. Review evidence and before/current hashes are stored under
`golden-review/`; reference regeneration is separate from behavior acceptance.
Four terminal-scene reference states did not fail in the current broad run;
old leftover failure PNGs are not presented as fresh V236 failures.

## Primary References

- [Firebase Flutter Google credential flow](https://firebase.google.com/docs/auth/flutter/federated-auth)
- [Firebase account linking](https://firebase.google.com/docs/auth/flutter/account-linking)
- [Official Android Google sign-in setup](https://github.com/flutter/packages/tree/main/packages/google_sign_in/google_sign_in_android)
- [Cinzel OFL](https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/OFL.txt)
- [Spectral OFL](https://raw.githubusercontent.com/google/fonts/main/ofl/spectral/OFL.txt)

These references establish supported API/license handling; they are not evidence
that the current project's external OAuth or Play configuration is correct.
