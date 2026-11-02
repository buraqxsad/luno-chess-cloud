import json,pathlib,hashlib,subprocess
from PIL import Image,ImageDraw,ImageFont,ImageChops
repo=pathlib.Path('/workspace/luno-chess'); out=pathlib.Path('/workspace/luno-review/bug-audit-round4/visual'); generated=pathlib.Path('/workspace/luno-review/bug-audit-round3/generated')
cases=json.load(open('/workspace/luno-review/bug-audit-round3/flutter/golden-comparison.json'))['cases']
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14)
rows=[]
for c in cases:
 p=pathlib.Path(c['path']);name=p.stem.replace('_testImage',''); group='battle' if 'battle_ui' in p.parts else 'card-art' if name=='battle-card-art-v204' else 'surface'
 ref=repo/p.parent.parent/'goldens'/f'{name}.png' if group!='surface' else repo/'luno_chess/qa/v203-after'/f'{name}.png'
 actual=generated/p
 assert ref.exists(), ref
 a=Image.open(actual).convert('RGBA');b=Image.open(ref).convert('RGBA');assert a.size==b.size
 diff=ImageChops.difference(a,b).convert('RGB'); bb=diff.getbbox();count=sum(1 for q in diff.getdata() if q!=(0,0,0))
 master=actual.with_name(name+'_masterImage.png')
 rows.append(dict(name=name,group=group,reference=str(ref),candidate=str(actual),reference_sha256=hashlib.sha256(ref.read_bytes()).hexdigest(),candidate_sha256=hashlib.sha256(actual.read_bytes()).hexdigest(),size=list(a.size),changed_pixels=count,changed_percent=100*count/(a.width*a.height),difference_bbox=list(bb) if bb else None,generated_master_matches_reference=master.exists() and master.read_bytes()==ref.read_bytes(),same_v239_candidate=c['same_v239_candidate']))
for group in ['battle','surface','card-art']:
 selected=[r for r in rows if r['group']==group]
 for start in range(0,len(selected),6):
  chunk=selected[start:start+6]; sheet=Image.new('RGB',(1500,1160),'#e7e7e7');d=ImageDraw.Draw(sheet)
  for j,r in enumerate(chunk):
   x=(j%3)*500;y=(j//3)*580
   d.text((x+6,y+3),f"{r['name']} ({r['changed_percent']:.2f}%)",fill='black',font=font)
   for col,key in enumerate(['reference','candidate']):
    im=Image.open(r[key]).convert('RGB');im.thumbnail((240,540))
    d.text((x+col*250+8,y+23),'TRACKED' if col==0 else 'ACTUAL R3',fill='black',font=font);sheet.paste(im,(x+col*250+4,y+42))
   r['contact_sheet']=f'{group}-{start//6+1:02}.png';r['sheet_position']=j+1
  sheet.save(out/f'{group}-{start//6+1:02}.png')
(out/'cases-metadata.json').write_text(json.dumps(rows,indent=2)+'\n')
print('Reference/candidate pairs:',len(rows),'all generated masters match tracked reference:',all(r['generated_master_matches_reference'] for r in rows))
print('group counts:',{g:sum(r['group']==g for r in rows) for g in ['battle','surface','card-art']})
print('sheets:',[p.name for p in sorted(out.glob('*.png'))])
