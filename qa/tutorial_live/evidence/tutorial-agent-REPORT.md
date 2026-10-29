# Tutorial bug hunt — scoped result

Confirmed production bugs found/fixed: **0**. No speculative fix was applied to explain the V240 emulator input failure.

Added `luno_chess/test/tutorial_live_safety_test.dart`: **8/8 PASS**, exit0, last run finished in3s under an explicit90s process timeout. Canonical evidence: `welcome-safety-final.log` and `welcome-safety-final-exit.txt`. No source/runtime, game rules, economy, asset or golden changes.

Coverage:
- TR/EN at320×568 text1.0,360×640 text1.6,430×932 text2.0: actual pointer taps traverse all3welcome steps. A saved callback from the prior frame cannot skip the next step. Reload restores welcomeStep3, does not complete tutorial, and preserves the full profile snapshot (canonical name fixture).
- Paused and covered-route callbacks do not advance; returning foreground/uncovering permits actual tap.
- Account-switch and disposed callbacks cannot advance the new account or grant rewards.

Static review: welcome lifecycle/ownership/route/TickerMode/load guards; advance/skip/dedup persistence; guided campaign callbacks; isolated introduction timers/details/finish; GameStore write/error handling. These checks did not establish a code cause for V240 native taps not progressing. Passing widget input does not establish native device or crash acceptance.

Harness history retained, not production failures: initial sandbox denied local socket; rerun used loopback network permission. Initial new fixture expected default mixed-case username unchanged after normal profile canonicalization; corrected fixture to a canonical username rather than weakening snapshot/economy assertions. Final account case initially waited on a Future created in widget fake zone; corrected using the existing real-zone create+bind fixture pattern. Two own pending runs overlapped briefly by mistake, then were both stopped and confirmed absent. Their shared/interrupted logs are diagnostic only; they are not passing evidence. Final unique log is authoritative.

No further Flutter jobs, emulator boots, commits, deploys or pushes by this agent.
