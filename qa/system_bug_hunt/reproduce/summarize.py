from pathlib import Path
import collections, hashlib, json, shutil, subprocess, sys

repo=Path('/workspace/luno-chess')
root=Path('/workspace/luno-review/system-bug-hunt')
tests={};suites={};counts=collections.Counter();per_file=collections.defaultdict(collections.Counter)
failures=[];outcomes=[];done=None
for line in (root/'flutter/full.jsonl').open():
    try: event=json.loads(line)
    except ValueError: continue
    kind=event.get('type')
    if kind=='suite': suites[event['suite']['id']]=event['suite']['path']
    elif kind=='testStart': tests[event['test']['id']]=event['test']
    elif kind=='testDone':
        test=tests.get(event['testID'],{})
        if event.get('hidden') and event.get('result')=='success': continue
        file=suites.get(test.get('suiteID'),'unknown').replace('/workspace/luno-chess/luno_chess/','')
        status='skip' if event.get('skipped') else event['result']
        counts[status]+=1;per_file[file][status]+=1
        row={'file':file,'name':test.get('name'),'status':status}
        outcomes.append(row)
        if status in ['error','failure']: failures.append(row)
    elif kind=='done': done=event
known={'test/battle_ui/visual_test.dart','test/visual_v203_test.dart','test/battle_card_art_v204_test.dart'}
summary={'counts':dict(counts),'suites':len(per_file),'done':done,'failures':failures,
         'non_historical_visual_failures':[row for row in failures if row['file'] not in known]}
(root/'flutter/summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
(root/'flutter/suite-outcomes.json').write_text(json.dumps(per_file,indent=2)+'\n')
(root/'flutter/test-outcomes.json').write_text(json.dumps(outcomes,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in ['failures','non_historical_visual_failures']}))
print('Non-historical visual failures:',len(summary['non_historical_visual_failures']))
if '--collect' not in sys.argv: raise SystemExit(0)
assert done is not None, 'Never collect active test outputs.'

def sha(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()

comparisons=[]
for folder in ['test/battle_ui/failures','test/failures']:
    for current in sorted((repo/'luno_chess'/folder).glob('*_testImage.png')):
        previous=Path('/workspace/luno-review/v239/generated/luno_chess')/folder/current.name
        comparisons.append({'path':str(current.relative_to(repo)),
                            'v239_exists':previous.exists(),
                            'same_v239_candidate':previous.exists() and sha(previous)==sha(current)})
(root/'flutter/golden-comparison.json').write_text(json.dumps({
    'checked':len(comparisons),'matching_v239':sum(r['same_v239_candidate'] for r in comparisons),
    'goldens_updated':False,'cases':comparisons},indent=2)+'\n')
dest=root/'generated';records=[]
changed=subprocess.check_output(['git','diff','--name-only','--','luno_chess/qa'],cwd=repo,text=True).splitlines()
allowed={'luno_chess/qa/rc/product-inventory.json','luno_chess/qa/source-audit/string-inventory.json'}
assert set(changed)<=allowed,changed
regression=json.loads((root/'source-commit.json').read_text())['full_regression_source_commit']
for name in changed:
    original=subprocess.check_output(['git','show','HEAD:'+name],cwd=repo)
    assert original==subprocess.check_output(['git','show',regression+':'+name],cwd=repo)
    target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);assert not target.exists()
    shutil.copy2(repo/name,target);(repo/name).write_bytes(original)
    records.append({'path':name,'tracked_fixture_restored_to_verified_pretest':True})
names=subprocess.check_output(['git','ls-files','--others','--exclude-standard','-z'],cwd=repo).decode().split('\0')
for name in names:
    if name and name.startswith(('luno_chess/qa/','luno_chess/test/battle_ui/failures/','luno_chess/test/failures/')):
        source=repo/name;target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);assert not target.exists()
        records.append({'path':name,'bytes':source.stat().st_size,'sha256':sha(source)})
        shutil.move(source,target)
dest.mkdir(exist_ok=True);(dest/'collection.json').write_text(json.dumps(records,indent=2)+'\n')
print('Collected',len(records),'generated evidence records; historical tracked fixtures retained.')
