import json,pathlib,hashlib,subprocess
p=pathlib.Path('/workspace/luno-review/bug-audit-round4/visual'); rs=json.load(open(p/'cases-metadata.json'))
battle_notes={
'arsenal-large-text':'Five visible list rows, 320x640 at 1.5 text; continuation is scroll content. Names/statuses remain legible.',
'arsenal':'Opponent 10-card arsenal: visible names and unused statuses preserved; scroll continuation present.',
'boardSeal':'e2-adjacent board-seal overlay and pieces/board geometry retained.',
'card-detail':'Shelter title, cost 2, own-piece target and duration/limits copy preserved; no missing paragraph visible.',
'cardBlock':'Modifier fixture retains dimmed shelter, cards/costs/status; no newly changed target.',
'chain':'e2 effect fixture, board and hand positions retained.',
'check':'e1 white king in check from e2 rook; red king square and chess instruction retained.',
'checkmate':'White-winner terminal: victory and checkmate reason retained; actions readable.',
'compact-four-large-text':'Both reference and candidate initial 320x640 text150 view clip hand/controls below viewport; current layout contains scroll containers, reachability not rerun.',
'compact-four':'Four costs 1/3/2/5 and names visible; lower continuation shared by reference.',
'compact':'320x640 base layout: board/hand visible, lower controls continue below view in both.',
'default':'Initial board, 6/6 own mana, 1/6 opponent mana, 3 cards at cost2 and pass action retained.',
'discount':'Discounted cost1 for three hand cards retained.',
'echo':'Echo modifier fixture: same hand/cost/board; effect behavior not inferred from static image.',
'fate-large-text':'Fate ordering at text150: Radar/Prophecy/Chain rows, up/down and disabled confirm retained.',
'fate':'Fate 3-row ordering and disabled confirm retained.',
'first-turn':'1/6 mana, dim cards, no card-stage action and first-turn chess instruction retained.',
'fog':'Fog zone around e2/f3 retained, pieces and hand unchanged.',
'four-card':'Four card costs1/3/2/5, hand4/4, deck6 and pass retained.',
'freeze':'Frozen e2 piece fixture retains board and hand positions.',
'large-text':'320x740 text150 initial image leaves pass/status below viewport in both; scroll reachability not rerun.',
'large':'430x932 layout keeps board, hand, pass, guide and deck footer visible.',
'lockedSquare':'e2 locked-square fixture retains target/effect board presentation.',
'long-tr':'Long opponent name uses ellipsis in both; no new text collision observed.',
'low-mana':'Own0/6, dimmed cards and pass retained; no unaffordable action appears active.',
'low-time':'Both clocks0:19 in red retained.',
'manaSabotage':'Shelter cost3 versus other cost2 cards retained.',
'match-menu':'Resign and leave-match commands retained in sheet.',
'mine-vow':'Combined hidden mine/vow e2 fixture: same visible disclosure as reference; image alone does not prove privacy.',
'mine':'Hidden mine fixture: same visible disclosure as reference; image alone does not prove privacy.',
'mismatch':'Projection error: disabled board/pass and retry action retained.',
'movement':'Special move target dots on third rank, highlighted b2/d2 and special-move guide retained.',
'multi-effect':'Combined overlay region near e2/f3 retained; effect semantics not proven by still image.',
'pending':'Confirming move status and disabled pass/retry actions retained.',
'piece-target':'Shelter targets own pieces, chosen e2 highlighted, Play enabled, mana2 and confirmation copy retained.',
'prophecy':'Two pending cards Radar/Chain, ordering controls and enabled confirm retained.',
'radar-stale':'Private info says Shelter not current; known upcoming Radar/Prophecy retained.',
'radar':'Private info says Shelter in hand; known upcoming Radar/Prophecy retained.',
'reconnect':'Reconnecting guide and disabled pass retained.',
'resign-confirm':'Resign confirmation sheet title and destructive command retained.',
'resign':'White-winner victory with resignation reason retained.',
'selected':'Shelter selected, own-piece target rings and disabled Play until target retained.',
'shelter':'Sheltered e2 overlay retained; no new target/geometry change observed.',
'slow':'Slow e2 effect fixture board/hand retained.',
'square-target':'Locked square chosen e4, dots only empty middle ranks, cost2 and enabled Play retained.',
'stalemate':'Draw/pat reason retained.',
'timeout':'Full-resolution check shows victory/Sure doldu for white winner, consistent with fixture; initial reduced-sheet suspicion withdrawn.',
'vow':'Vow e2 fixture has same public presentation; no privacy behavior inferred.',
'zero-card':'Empty hand, own6/6, deck10, pass and move guidance retained.',
'zone':'Fog e4/f4/e5/f5 2x2 target, rings/dots and zone confirmation copy retained.'}
surface_notes={
'achievements':'Offline-load error and retry retained; no success state inferred.',
'arenas':'Arena1,0/100,next100 and reward previews retained; text/control raster differences only visibly material.',
'browser':'Legacy-card archive label and locked/unlocked grid retained; not active Battle V1 catalog.',
'cards':'Current explicit back arrow added; 24-card preview grid and loading spinner remain. Navigation fixture is offline, not live ownership acceptance.',
'chest':'Cosmetic chest gold1500/gems30 and collect command retained.',
'collection':'Battle24-card count and four category links retained.',
'costumes':'White/black selector and owned/locked costume entries retained.',
'daily-reward':'500-gold reward dialog retained; not proof a backend grant happened.',
'deck':'Current back arrow and multi-line affordability/target guidance added; pushes save/other cards lower. V236 FINDINGS documents guidance addition; scroll reachability not rerun.',
'defeat':'Defeat state with replay/home retained.',
'difficulty':'Six AI trainers and trophy labels retained.',
'dm':'Loading spinner and composer retained in offline fixture; loaded conversation not covered.',
'draw':'Draw result and replay/home retained.',
'edit-profile':'Country, bio counter27/160 and avatar selector retained.',
'emojis':'0/4 selected and owned/locked emoji grid retained.',
'friendly':'Create room and join code controls retained,5-minute policy visible.',
'friends':'Lookup/requests/ranking controls retained; loading spinner is fixture state.',
'guide':'Large documented V237 replacement: interactive hub, mascot, academy/card links and mini-board replace prose. Visual design approval record for exact replacement absent.',
'history':'Empty match-history state retained.',
'home':'First-match CTA, arena0/100 and navigation remain readable; CTA/typography metrics differ.',
'inbox':'Loading fixture retained; does not cover loaded/empty/error notifications.',
'levels':'Level1,next2,+140 gold preview retained.',
'missions':'Offline mission-load failure and retry retained.',
'pass':'0/30 progress, separate450-gem Pass Premium and reward tracks retained.',
'play':'Starter-deck offline preview and ranked/training modes retained.',
'premium':'Unverified membership, disabled purchase options and benefits retained.',
'profile':'Profile/bio/stats/gold1250/gems42 retained.',
'promotion':'Both images show missing Turkish dotted I glyphs in PİYON VADİSİ; current explicit Cinzel plus inherited Spectral TR chain lacks U+0130. Reported to root for current focused reproduction/fix.',
'public-profile':'Deniz,1450 trophies,84 wins,70% retained.',
'queue':'Offline connection-required queue state and reconnect retained.',
'ranking':'Offline ranking failure and retry retained.',
'season-reward':'HUKUMDAR,500gold/20gems and claim retained.',
'season':'Season not ready/offline and retry retained.',
'settings':'Same language/audio/vibration/account controls; typography/control-spacing differences remain readable. Exact design signoff unavailable.',
'shop':'Premium/Pass/daily-gift/cosmetic chest sections retained; reward200 and chest500 visible.',
'victory':'Victory/reward50/replay/home retained.',
}
for n in ['tutorial']+[f'tutorial-{i}' for i in range(1,10)]:
 surface_notes[n]={
 'tutorial':'Welcome step1/10, Luno portrait and next retained; header adds catalog/academy actions.',
 'tutorial-1':'Step2/10 first move: white TutorialCoach styling and small stage shift; pieces/first-turn restriction retained.',
 'tutorial-2':'Step3/10: white coach, same skip-card instruction and board position.',
 'tutorial-3':'Step4/10: white coach and reflowed mana slider/cost row, opponent-card target instruction retained.',
 'tutorial-4':'Step5/10: white coach plus disabled target-selection command move board down; black c7/f7/d5 rings retained.',
 'tutorial-5':'Step6/10: same reflow/disabled target-selection command, white own-piece targets retained.',
 'tutorial-6':'Step7/10: white coach, skip-card instruction and board retained.',
 'tutorial-7':'Step8/10: white coach, Radar/Prophecy and opposing-card choices retained.',
 'tutorial-8':'Step9/10 ranked/training/5+2 instruction retained; same two mode icons and next.',
 'tutorial-9':'Step10/10 first-match guidance copy updated; four lesson cards and Play transition retained. DEVAM tutorial-live notes describe guided first match.'}[n]
for r in rs:
 g=r['group'];n=r['name']
 r['inspection']={'contact_sheet':True,'full_resolution':(p/f'detail-{g}-{n}.png').exists(),'verdict':'no_new_semantic_delta_observed','golden_acceptance':'unresolved_fail','notes':battle_notes[n] if g=='battle' else surface_notes[n] if g=='surface' else 'All24 distinct art images/layout preserved; enhanced diff isolates card wire-label text edges, no art-pixel change in grid.'}
 if g=='surface' and n=='promotion':r['inspection']['verdict']='visible_glyph_defect_current_declared_font_chain'
 elif g=='surface' and (n=='guide' or n=='deck' or n=='cards' or n.startswith('tutorial')):r['inspection']['verdict']='existing_design_or_guidance_delta_without_exact_signoff'
 elif g=='surface':r['inspection']['verdict']='text_or_control_metrics_delta_no_semantic_regression_observed'
 elif g=='card-art':r['inspection']['verdict']='text_edge_delta_art_unchanged_observed'
 else:r['inspection']['verdict']='text_edge_delta_no_target_rule_layout_regression_observed'
(p/'cases-reviewed.json').write_text(json.dumps(rs,ensure_ascii=False,indent=2)+'\n')
md=['# Per-case visual inspection','', 'All97 original comparisons remain FAIL. A row is an inspection result, never approval to replace a golden. The images are deterministic Flutter widget captures, not Android/native screenshots.','', '| Group | Case | Changed pixels % | Inspection | Detail |','| --- | --- | ---: | --- | --- |']
for r in rs:
 i=r['inspection'];md.append(f"| {r['group']} | {r['name']} | {r['changed_percent']:.3f} | {i['notes']} | [{r['contact_sheet']}, item{r['sheet_position']}]({r['contact_sheet']}){' / [full](detail-'+r['group']+'-'+r['name']+'.png)' if i['full_resolution'] else ''} |")
(p/'MATRIX.md').write_text('\n'.join(md)+'\n')
print('Saved97 individually annotated rows; detailed pairs',sum(r['inspection']['full_resolution'] for r in rs))
