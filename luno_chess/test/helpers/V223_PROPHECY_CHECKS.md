# Independent Prophecy check provenance

The initial cloud transfer omitted the original
`qa/v223/prophecy/independent_checks.dart`. No copy exists in the available
repository commit or branch. `v223_prophecy_independent_checks.dart` is a new
replacement authored on 28 October 2026, not a recovered original.

Its chess expectations use the existing hand-authored allowed/forbidden UCI
positions in `v223_prophecy_cases.dart`, with a rank-only mirror for black.
It checks the authored geometry both before and after a Prophecy cast and
resolution. It does not create expected moves by querying the legal generator.

Its accounting/pending/privacy expectations implement the published card text
and `battle_contract/v1/rules.json`'s `prophecy-invalid-permutations` fixture:
inspect up to two top cards, reorder that exact set, draw none, spend one mana
once, retain the acting side/board and move on to the chess phase. The retained
fixture deck lists supply literal input card orders. The engine is exercised
only to obtain observed results, never to create expected answers.

Deliberately wrong move sets and outcomes must be rejected by each expectation
family (allowed/forbidden geometry; mana/hand/deck/draw accounting; pending owner,
phase/turn; and opponent private reveals). All pre-existing adversarial,
controller recovery and widget assertions remain in place.

This is new coverage with explicit provenance; it does not claim to reproduce
the unavailable original module's exact cases or historical test counts.
