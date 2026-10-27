const fs = require('fs'), path = require('path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
(async () => {
  const files = fs.readdirSync(path.join(root, 'assets/native_art')).filter(f => f.startsWith('polish-v203-'));
  const results = [];
  for (const file of files) {
    const image = sharp(path.join(root, 'assets/native_art', file));
    const meta = await image.metadata(), stats = await image.stats();
    const effect = /-(cast|reward|cleanse|impact)\./.test(file);
    const button = /-(button|tab)-/.test(file);
    const expected = effect ? [256, 256] : button ? [512, 128] : [512, 288];
    results.push({file, width:meta.width, height:meta.height, alpha:meta.hasAlpha,
      nonblank:stats.channels.some(c => c.stdev > 1), bytes:fs.statSync(path.join(root, 'assets/native_art',file)).size,
      pass:meta.width===expected[0] && meta.height===expected[1] && meta.hasAlpha && stats.channels.some(c=>c.stdev>1)});
  }
  const report = {pass:files.length===14 && results.every(r=>r.pass), files:results,
    bytes:results.reduce((sum, r)=>sum+r.bytes,0), decodedBytes:results.reduce((sum,r)=>sum+r.width*r.height*4,0)};
  fs.writeFileSync(path.join(root,'qa/v203-art-validation.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify({pass:report.pass, assets:files.length,bytes:report.bytes,decodedBytes:report.decodedBytes}));
  if(!report.pass) process.exitCode=1;
})();
