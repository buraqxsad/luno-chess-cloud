# Per-case visual inspection

All97 original comparisons remain FAIL. A row is an inspection result, never approval to replace a golden. The images are deterministic Flutter widget captures, not Android/native screenshots.

| Group | Case | Changed pixels % | Inspection | Detail |
| --- | --- | ---: | --- | --- |
| battle | arsenal-large-text | 4.142 | Five visible list rows, 320x640 at 1.5 text; continuation is scroll content. Names/statuses remain legible. | [battle-01.png, item1](battle-01.png) |
| battle | arsenal | 2.434 | Opponent 10-card arsenal: visible names and unused statuses preserved; scroll continuation present. | [battle-01.png, item2](battle-01.png) |
| battle | boardSeal | 1.826 | e2-adjacent board-seal overlay and pieces/board geometry retained. | [battle-01.png, item3](battle-01.png) |
| battle | card-detail | 4.012 | Shelter title, cost 2, own-piece target and duration/limits copy preserved; no missing paragraph visible. | [battle-01.png, item4](battle-01.png) |
| battle | cardBlock | 1.826 | Modifier fixture retains dimmed shelter, cards/costs/status; no newly changed target. | [battle-01.png, item5](battle-01.png) |
| battle | chain | 1.826 | e2 effect fixture, board and hand positions retained. | [battle-01.png, item6](battle-01.png) |
| battle | check | 1.802 | e1 white king in check from e2 rook; red king square and chess instruction retained. | [battle-02.png, item1](battle-02.png) |
| battle | checkmate | 0.930 | White-winner terminal: victory and checkmate reason retained; actions readable. | [battle-02.png, item2](battle-02.png) |
| battle | compact-four-large-text | 1.429 | Both reference and candidate initial 320x640 text150 view clip hand/controls below viewport; current layout contains scroll containers, reachability not rerun. | [battle-02.png, item3](battle-02.png) / [full](detail-battle-compact-four-large-text.png) |
| battle | compact-four | 1.790 | Four costs 1/3/2/5 and names visible; lower continuation shared by reference. | [battle-02.png, item4](battle-02.png) |
| battle | compact | 1.328 | 320x640 base layout: board/hand visible, lower controls continue below view in both. | [battle-02.png, item5](battle-02.png) |
| battle | default | 1.826 | Initial board, 6/6 own mana, 1/6 opponent mana, 3 cards at cost2 and pass action retained. | [battle-02.png, item6](battle-02.png) / [full](detail-battle-default.png) |
| battle | discount | 1.814 | Discounted cost1 for three hand cards retained. | [battle-03.png, item1](battle-03.png) |
| battle | echo | 1.826 | Echo modifier fixture: same hand/cost/board; effect behavior not inferred from static image. | [battle-03.png, item2](battle-03.png) |
| battle | fate-large-text | 3.525 | Fate ordering at text150: Radar/Prophecy/Chain rows, up/down and disabled confirm retained. | [battle-03.png, item3](battle-03.png) |
| battle | fate | 1.402 | Fate 3-row ordering and disabled confirm retained. | [battle-03.png, item4](battle-03.png) |
| battle | first-turn | 1.656 | 1/6 mana, dim cards, no card-stage action and first-turn chess instruction retained. | [battle-03.png, item5](battle-03.png) |
| battle | fog | 1.826 | Fog zone around e2/f3 retained, pieces and hand unchanged. | [battle-03.png, item6](battle-03.png) |
| battle | four-card | 2.137 | Four card costs1/3/2/5, hand4/4, deck6 and pass retained. | [battle-04.png, item1](battle-04.png) |
| battle | freeze | 1.826 | Frozen e2 piece fixture retains board and hand positions. | [battle-04.png, item2](battle-04.png) |
| battle | large-text | 1.488 | 320x740 text150 initial image leaves pass/status below viewport in both; scroll reachability not rerun. | [battle-04.png, item3](battle-04.png) / [full](detail-battle-large-text.png) |
| battle | large | 1.500 | 430x932 layout keeps board, hand, pass, guide and deck footer visible. | [battle-04.png, item4](battle-04.png) |
| battle | lockedSquare | 1.826 | e2 locked-square fixture retains target/effect board presentation. | [battle-04.png, item5](battle-04.png) |
| battle | long-tr | 2.026 | Long opponent name uses ellipsis in both; no new text collision observed. | [battle-04.png, item6](battle-04.png) |
| battle | low-mana | 1.826 | Own0/6, dimmed cards and pass retained; no unaffordable action appears active. | [battle-05.png, item1](battle-05.png) |
| battle | low-time | 1.819 | Both clocks0:19 in red retained. | [battle-05.png, item2](battle-05.png) |
| battle | manaSabotage | 1.832 | Shelter cost3 versus other cost2 cards retained. | [battle-05.png, item3](battle-05.png) |
| battle | match-menu | 1.122 | Resign and leave-match commands retained in sheet. | [battle-05.png, item4](battle-05.png) |
| battle | mine-vow | 1.826 | Combined hidden mine/vow e2 fixture: same visible disclosure as reference; image alone does not prove privacy. | [battle-05.png, item5](battle-05.png) |
| battle | mine | 1.826 | Hidden mine fixture: same visible disclosure as reference; image alone does not prove privacy. | [battle-05.png, item6](battle-05.png) |
| battle | mismatch | 1.498 | Projection error: disabled board/pass and retry action retained. | [battle-06.png, item1](battle-06.png) |
| battle | movement | 1.600 | Special move target dots on third rank, highlighted b2/d2 and special-move guide retained. | [battle-06.png, item2](battle-06.png) |
| battle | multi-effect | 1.826 | Combined overlay region near e2/f3 retained; effect semantics not proven by still image. | [battle-06.png, item3](battle-06.png) |
| battle | pending | 1.376 | Confirming move status and disabled pass/retry actions retained. | [battle-06.png, item4](battle-06.png) |
| battle | piece-target | 1.884 | Shelter targets own pieces, chosen e2 highlighted, Play enabled, mana2 and confirmation copy retained. | [battle-06.png, item5](battle-06.png) / [full](detail-battle-piece-target.png) |
| battle | prophecy | 1.428 | Two pending cards Radar/Chain, ordering controls and enabled confirm retained. | [battle-06.png, item6](battle-06.png) |
| battle | radar-stale | 1.356 | Private info says Shelter not current; known upcoming Radar/Prophecy retained. | [battle-07.png, item1](battle-07.png) |
| battle | radar | 1.270 | Private info says Shelter in hand; known upcoming Radar/Prophecy retained. | [battle-07.png, item2](battle-07.png) |
| battle | reconnect | 1.664 | Reconnecting guide and disabled pass retained. | [battle-07.png, item3](battle-07.png) |
| battle | resign-confirm | 1.436 | Resign confirmation sheet title and destructive command retained. | [battle-07.png, item4](battle-07.png) |
| battle | resign | 0.971 | White-winner victory with resignation reason retained. | [battle-07.png, item5](battle-07.png) |
| battle | selected | 1.807 | Shelter selected, own-piece target rings and disabled Play until target retained. | [battle-07.png, item6](battle-07.png) |
| battle | shelter | 1.826 | Sheltered e2 overlay retained; no new target/geometry change observed. | [battle-08.png, item1](battle-08.png) |
| battle | slow | 1.826 | Slow e2 effect fixture board/hand retained. | [battle-08.png, item2](battle-08.png) |
| battle | square-target | 1.928 | Locked square chosen e4, dots only empty middle ranks, cost2 and enabled Play retained. | [battle-08.png, item3](battle-08.png) / [full](detail-battle-square-target.png) |
| battle | stalemate | 0.997 | Draw/pat reason retained. | [battle-08.png, item4](battle-08.png) |
| battle | timeout | 0.955 | Full-resolution check shows victory/Sure doldu for white winner, consistent with fixture; initial reduced-sheet suspicion withdrawn. | [battle-08.png, item5](battle-08.png) / [full](detail-battle-timeout.png) |
| battle | vow | 1.826 | Vow e2 fixture has same public presentation; no privacy behavior inferred. | [battle-08.png, item6](battle-08.png) |
| battle | zero-card | 1.718 | Empty hand, own6/6, deck10, pass and move guidance retained. | [battle-09.png, item1](battle-09.png) |
| battle | zone | 1.946 | Fog e4/f4/e5/f5 2x2 target, rings/dots and zone confirmation copy retained. | [battle-09.png, item2](battle-09.png) |
| surface | achievements | 0.732 | Offline-load error and retry retained; no success state inferred. | [surface-01.png, item1](surface-01.png) |
| surface | arenas | 4.942 | Arena1,0/100,next100 and reward previews retained; text/control raster differences only visibly material. | [surface-01.png, item2](surface-01.png) |
| card-art | battle-card-art-v204 | 1.014 | All24 distinct art images/layout preserved; enhanced diff isolates card wire-label text edges, no art-pixel change in grid. | [card-art-01.png, item1](card-art-01.png) / [full](detail-card-art-battle-card-art-v204.png) |
| surface | browser | 2.335 | Legacy-card archive label and locked/unlocked grid retained; not active Battle V1 catalog. | [surface-01.png, item3](surface-01.png) |
| surface | cards | 2.054 | Current explicit back arrow added; 24-card preview grid and loading spinner remain. Navigation fixture is offline, not live ownership acceptance. | [surface-01.png, item4](surface-01.png) |
| surface | chest | 0.671 | Cosmetic chest gold1500/gems30 and collect command retained. | [surface-01.png, item5](surface-01.png) |
| surface | collection | 2.980 | Battle24-card count and four category links retained. | [surface-01.png, item6](surface-01.png) |
| surface | costumes | 3.005 | White/black selector and owned/locked costume entries retained. | [surface-02.png, item1](surface-02.png) |
| surface | daily-reward | 0.587 | 500-gold reward dialog retained; not proof a backend grant happened. | [surface-02.png, item2](surface-02.png) |
| surface | deck | 21.147 | Current back arrow and multi-line affordability/target guidance added; pushes save/other cards lower. V236 FINDINGS documents guidance addition; scroll reachability not rerun. | [surface-02.png, item3](surface-02.png) / [full](detail-surface-deck.png) |
| surface | defeat | 0.946 | Defeat state with replay/home retained. | [surface-02.png, item4](surface-02.png) |
| surface | difficulty | 2.933 | Six AI trainers and trophy labels retained. | [surface-02.png, item5](surface-02.png) |
| surface | dm | 0.194 | Loading spinner and composer retained in offline fixture; loaded conversation not covered. | [surface-02.png, item6](surface-02.png) |
| surface | draw | 0.832 | Draw result and replay/home retained. | [surface-03.png, item1](surface-03.png) |
| surface | edit-profile | 1.392 | Country, bio counter27/160 and avatar selector retained. | [surface-03.png, item2](surface-03.png) |
| surface | emojis | 1.854 | 0/4 selected and owned/locked emoji grid retained. | [surface-03.png, item3](surface-03.png) |
| surface | friendly | 2.484 | Create room and join code controls retained,5-minute policy visible. | [surface-03.png, item4](surface-03.png) |
| surface | friends | 1.015 | Lookup/requests/ranking controls retained; loading spinner is fixture state. | [surface-03.png, item5](surface-03.png) |
| surface | guide | 90.819 | Large documented V237 replacement: interactive hub, mascot, academy/card links and mini-board replace prose. Visual design approval record for exact replacement absent. | [surface-03.png, item6](surface-03.png) / [full](detail-surface-guide.png) |
| surface | history | 1.224 | Empty match-history state retained. | [surface-04.png, item1](surface-04.png) |
| surface | home | 6.017 | First-match CTA, arena0/100 and navigation remain readable; CTA/typography metrics differ. | [surface-04.png, item2](surface-04.png) |
| surface | inbox | 0.201 | Loading fixture retained; does not cover loaded/empty/error notifications. | [surface-04.png, item3](surface-04.png) |
| surface | levels | 2.126 | Level1,next2,+140 gold preview retained. | [surface-04.png, item4](surface-04.png) |
| surface | missions | 1.548 | Offline mission-load failure and retry retained. | [surface-04.png, item5](surface-04.png) |
| surface | pass | 2.364 | 0/30 progress, separate450-gem Pass Premium and reward tracks retained. | [surface-04.png, item6](surface-04.png) |
| surface | play | 3.754 | Starter-deck offline preview and ranked/training modes retained. | [surface-05.png, item1](surface-05.png) |
| surface | premium | 4.874 | Unverified membership, disabled purchase options and benefits retained. | [surface-05.png, item2](surface-05.png) |
| surface | profile | 2.568 | Profile/bio/stats/gold1250/gems42 retained. | [surface-05.png, item3](surface-05.png) |
| surface | promotion | 3.644 | Both images show missing Turkish dotted I glyphs in PİYON VADİSİ; current explicit Cinzel plus inherited Spectral TR chain lacks U+0130. Reported to root for current focused reproduction/fix. | [surface-05.png, item4](surface-05.png) / [full](detail-surface-promotion.png) |
| surface | public-profile | 1.334 | Deniz,1450 trophies,84 wins,70% retained. | [surface-05.png, item5](surface-05.png) |
| surface | queue | 2.530 | Offline connection-required queue state and reconnect retained. | [surface-05.png, item6](surface-05.png) |
| surface | ranking | 0.850 | Offline ranking failure and retry retained. | [surface-06.png, item1](surface-06.png) |
| surface | season-reward | 1.129 | HUKUMDAR,500gold/20gems and claim retained. | [surface-06.png, item2](surface-06.png) |
| surface | season | 0.954 | Season not ready/offline and retry retained. | [surface-06.png, item3](surface-06.png) |
| surface | settings | 8.777 | Same language/audio/vibration/account controls; typography/control-spacing differences remain readable. Exact design signoff unavailable. | [surface-06.png, item4](surface-06.png) / [full](detail-surface-settings.png) |
| surface | shop | 3.345 | Premium/Pass/daily-gift/cosmetic chest sections retained; reward200 and chest500 visible. | [surface-06.png, item5](surface-06.png) |
| surface | tutorial-1 | 20.017 | Step2/10 first move: white TutorialCoach styling and small stage shift; pieces/first-turn restriction retained. | [surface-06.png, item6](surface-06.png) |
| surface | tutorial-2 | 16.517 | Step3/10: white coach, same skip-card instruction and board position. | [surface-07.png, item1](surface-07.png) |
| surface | tutorial-3 | 27.392 | Step4/10: white coach and reflowed mana slider/cost row, opponent-card target instruction retained. | [surface-07.png, item2](surface-07.png) |
| surface | tutorial-4 | 30.865 | Step5/10: white coach plus disabled target-selection command move board down; black c7/f7/d5 rings retained. | [surface-07.png, item3](surface-07.png) / [full](detail-surface-tutorial-4.png) |
| surface | tutorial-5 | 31.099 | Step6/10: same reflow/disabled target-selection command, white own-piece targets retained. | [surface-07.png, item4](surface-07.png) |
| surface | tutorial-6 | 16.608 | Step7/10: white coach, skip-card instruction and board retained. | [surface-07.png, item5](surface-07.png) |
| surface | tutorial-7 | 24.403 | Step8/10: white coach, Radar/Prophecy and opposing-card choices retained. | [surface-07.png, item6](surface-07.png) |
| surface | tutorial-8 | 4.202 | Step9/10 ranked/training/5+2 instruction retained; same two mode icons and next. | [surface-08.png, item1](surface-08.png) |
| surface | tutorial-9 | 6.316 | Step10/10 first-match guidance copy updated; four lesson cards and Play transition retained. DEVAM tutorial-live notes describe guided first match. | [surface-08.png, item2](surface-08.png) |
| surface | tutorial | 2.190 | Welcome step1/10, Luno portrait and next retained; header adds catalog/academy actions. | [surface-08.png, item3](surface-08.png) |
| surface | victory | 0.923 | Victory/reward50/replay/home retained. | [surface-08.png, item4](surface-08.png) |
