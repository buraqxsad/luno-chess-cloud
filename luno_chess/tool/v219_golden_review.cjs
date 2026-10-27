const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const surfaces = process.argv[2] === 'surfaces';
const surfaceNames = new Set(['cards','deck','play','tutorial-7','tutorial-9']);
const before = path.join(root, `qa/v219/before/goldens/${surfaces ? 'surfaces' : 'battle'}`);
const failures = path.join(root, surfaces ? 'test/failures' : 'test/battle_ui/failures');
const output = path.join(root, surfaces ? 'qa/v219/surface-golden-review' : 'qa/v219/golden-review');

async function main() {
  fs.mkdirSync(output, {recursive: true});
  const baseline = JSON.parse(fs.readFileSync(path.join(root,'qa/v219/source-lock-before.json'),'utf8'));
  const earliest = Date.parse(baseline.recordedAt) - 1000;
  const names = fs.readdirSync(failures).filter(name => name.endsWith('_testImage.png') &&
      (!surfaces || surfaceNames.has(name.replace('_testImage.png',''))) &&
      fs.statSync(path.join(failures,name)).mtimeMs >= earliest)
    .map(name => name.replace('_testImage.png', '')).sort();
  const metrics = [];
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    const oldPath = path.join(before, `${name}.png`);
    if (!fs.existsSync(oldPath)) continue;
    const newPath = path.join(failures, `${name}_testImage.png`);
    const old = await sharp(oldPath).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    const current = await sharp(newPath).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    if (old.info.width !== current.info.width || old.info.height !== current.info.height) {
      throw Error(`Dimensions changed: ${name}`);
    }
    let left = old.info.width, top = old.info.height, right = -1, bottom = -1, pixels = 0;
    for (let pixel = 0; pixel < old.info.width * old.info.height; pixel++) {
      const offset = pixel * 4;
      if ([0,1,2,3].some(channel => old.data[offset+channel] !== current.data[offset+channel])) {
        const x = pixel % old.info.width, y = Math.floor(pixel / old.info.width);
        left = Math.min(left,x); right = Math.max(right,x);
        top = Math.min(top,y); bottom = Math.max(bottom,y); pixels++;
      }
    }
    metrics.push({name, width:old.info.width, height:old.info.height,
      changedPixels:pixels, bounds:pixels ? {left,top,right,bottom} : null});
    fs.copyFileSync(newPath, path.join(output, `${name}.png`));
  }
  for (let start = 0; start < names.length; start += 3) {
    const composites = [];
    const page = names.slice(start,start+3);
    for (const [row,name] of page.entries()) {
      for (const [column, file] of [path.join(before,`${name}.png`),path.join(output,`${name}.png`)].entries()) {
        const tile = await sharp(file).resize(300,600,{fit:'contain',background:'#091219'}).png().toBuffer();
        const label = Buffer.from(`<svg width="300" height="24"><rect width="300" height="24" fill="#091219"/><text x="6" y="17" font-family="Arial" font-size="12" fill="white">${name} - ${column ? 'current' : 'baseline'}</text></svg>`);
        composites.push({input:label,left:column*300,top:row*624},
          {input:tile,left:column*300,top:row*624+24});
      }
    }
    await sharp({create:{width:600,height:page.length*624,channels:4,background:'#091219'}})
      .composite(composites).png().toFile(path.join(output,`pairs-${String(start/3+1).padStart(2,'0')}.png`));
  }
  fs.writeFileSync(path.join(output,'pixel-diff-metrics.json'),JSON.stringify(metrics,null,2));
  console.log(JSON.stringify({reviewedByScript:metrics.length,metrics:metrics.map(x=>({name:x.name,bounds:x.bounds,changedPixels:x.changedPixels}))},null,2));
}

main().catch(error=>{console.error(error);process.exitCode=1;});
