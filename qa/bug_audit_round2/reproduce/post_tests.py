from pathlib import Path
import collections, hashlib, json, os, shutil
r=Path('/workspace/luno-review/bug-audit-round2')
s=json.loads((r/'flutter/summary.json').read_text());previous=json.loads(Path('/workspace/luno-review/v240/flutter/summary.json').read_text())
known={(x['file'],x['name']) for x in previous['failures']}
tests={}; messages=collections.defaultdict(list)
for line in (r/'flutter/full.jsonl').open():
    try:e=json.loads(line)
    except ValueError:continue
    if e.get('type')=='testStart':tests[e['test']['id']]=e['test']
    if e.get('type') in ['error','print']:messages[e.get('testID')].append(e.get('message',e.get('error','')))
cases=[]
for x in s['failures']:
    ids=[i for i,t in tests.items() if t['name']==x['name']]
    pixel=any('Pixel test failed' in str(msg) for i in ids for msg in messages[i])
    cases.append({**x,'same_v240_failed_case':(x['file'],x['name']) in known,'pixel_failure_confirmed':pixel})
classification={'cases':cases,'all_failures_are_existing_pixel_comparisons':all(x['same_v240_failed_case'] and x['pixel_failure_confirmed'] for x in cases),'golden_reference_updates':0}
(r/'flutter/failure-classification.json').write_text(json.dumps(classification,indent=2)+'\n')
assert classification['all_failures_are_existing_pixel_comparisons'], 'Investigate new functional or visual failures before packaging.'
comparison=json.loads((r/'flutter/golden-comparison.json').read_text())
assert comparison['checked']==len(cases), 'Every pixel failure needs its own current candidate image.'
assert comparison['matching_v239']==comparison['checked'], 'Changed visual candidates require review; matching old test names is not acceptance.'
seen={};saved=0;count=0
for folder in ['v238/generated','v239/generated','v240/generated','tutorial-live/interrupted-before-availability-fix/generated','tutorial-live/narrow-generated','tutorial-live/generated','system-bug-hunt/generated','bug-audit-round2/generated']:
    for p in sorted((Path('/workspace/luno-review')/folder).rglob('*')):
        if not p.is_file() or p.is_symlink() or p.stat().st_size<4096:continue
        st=p.stat()
        with p.open('rb') as f:key=(st.st_size,hashlib.file_digest(f,'sha256').digest())
        other=seen.get(key)
        if other is None:seen[key]=p;continue
        if other.stat().st_ino==st.st_ino:continue
        tmp=p.with_name(p.name+'.bug-audit-round2-tmp');assert not tmp.exists()
        os.link(other,tmp);os.replace(tmp,p);count+=1;saved+=st.st_size
removed=[]
for name in ['test_cache','unit_test_assets']:
    p=Path('/workspace/luno-chess/luno_chess/build')/name
    if p.exists():
        size=sum(f.stat().st_size for f in p.rglob('*') if f.is_file());shutil.rmtree(p);removed.append({'path':str(p),'bytes':size})
(r/'android/disk-recovery.json').write_text(json.dumps({'immutable_evidence_contents_retained':True,'hardlinked_identical_files':count,'bytes_saved':saved,'rebuildable_test_outputs_removed_only_after_full_tests':removed},indent=2)+'\n')
print('Verified failure scope and reclaimed only duplicate/generated test storage.')
