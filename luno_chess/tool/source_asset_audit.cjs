const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const files = dir => fs.readdirSync(path.join(root, dir), {withFileTypes:true}).flatMap(e => e.isDirectory() ? files(`${dir}/${e.name}`) : [`${dir}/${e.name}`]);
const source = new Map(files('lib').filter(f => f.endsWith('.dart')).map(f => [f, read(f)]));
const reachable = new Set();
function visit(file) {
  if (reachable.has(file) || !source.has(file)) return;
  reachable.add(file);
  for (const m of source.get(file).matchAll(/(?:import|export)\s+['"]([^'"]+)['"]/g)) {
    if (m[1].startsWith('package:luno_chess/')) visit('lib/'+m[1].slice('package:luno_chess/'.length));
    else if (!m[1].includes(':')) visit(path.posix.normalize(path.posix.join(path.posix.dirname(file), m[1])));
  }
}
visit('lib/main.dart');
const testSources = files('test').filter(f => f.endsWith('.dart')).map(f => [f, read(f)]);
const rendered = new Set();
for (const file of files('qa/source-audit/screens').filter(f => f.endsWith('.assets.json'))) for (const asset of JSON.parse(read(file))) rendered.add(asset);
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function references(asset, entries) {
  const basename = path.posix.basename(asset);
  return entries.filter(([, text]) => {
    if (text.includes(asset) || text.includes(basename)) return true;
    for (const m of text.matchAll(/['"](assets\/[^'"\r\n]+)['"]/g)) {
      if (!m[1].includes('$')) continue;
      // A whole interpolated filename is not proof that every asset is used.
      // Literal filenames in its data table are handled by the checks above.
      const templateBasename = path.posix.basename(m[1]);
      if (/^\$(?:\{.*\}|[A-Za-z_]\w*)$/.test(templateBasename)) continue;
      const pattern = escape(m[1]).replace(/\\\$\\\{.*?\\\}|\\\$[A-Za-z_][\w.]*/g, '.*');
      if (new RegExp('^'+pattern+'$').test(asset)) return true;
    }
    return false;
  }).map(([file]) => file);
}
async function main() {
  const inventory = [];
  for (const asset of files('assets').filter(f => /\.(png|webp|gif|jpg|jpeg)$/.test(f))) {
    const refs = references(asset, [...source].filter(([f]) => reachable.has(f)));
    const test = references(asset, testSources);
    const historical = references(asset, [...source].filter(([f]) => !reachable.has(f)));
    const status = rendered.has(asset) || refs.length && /battle-v202b-|luno-portrait-v212|loading-scene-v212|battle-action-face-v212/.test(asset) ? 'CURRENT APPROVED' : refs.length ? 'LEGACY BUT STILL USED' : test.length || historical.length ? 'TEST/REFERENCE' : 'UNUSED';
    inventory.push({asset, status, bytes:fs.statSync(path.join(root, asset)).size, productionReferences:refs, testReferences:test, historicalReferences:historical, renderedInThisAudit:rendered.has(asset), confidence:rendered.has(asset)?'rendered screenshot':'conservative static/template reachability; no deletion authorized'});
  }
  const icons = [];
  for (const [density, size] of [['mdpi',48],['hdpi',72],['xhdpi',96],['xxhdpi',144],['xxxhdpi',192]]) {
    const file = `android/app/src/main/res/mipmap-${density}/ic_launcher.png`;
    const metadata = await sharp(path.join(root,file)).metadata();
    if (metadata.width !== size || metadata.height !== size) throw new Error('Wrong launcher size: '+density);
    const raw = await sharp(path.join(root,file)).removeAlpha().raw().toBuffer();
    let warm=0, navy=0, flutterBlue=0;
    for(let i=0;i<raw.length;i+=3){const [r,g,b]=raw.subarray(i,i+3);if(r>150&&g>90&&b<g)warm++;if(r<30&&g<35&&b<40)navy++;if(r<60&&g>140&&b>200)flutterBlue++;}
    if(warm< size*size*.08 || navy<size*size*.25 || flutterBlue>size*size*.01)throw new Error('Unexpected launcher color/content: '+density);
    icons.push({density,size,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex'),warmPixels:warm,navyPixels:navy,flutterBluePixels:flutterBlue});
  }
  const counts={'CURRENT APPROVED':0,'LEGACY BUT STILL USED':0,'UNUSED':0,'TEST/REFERENCE':0};for(const row of inventory)counts[row.status]++;
  const result={counts,reachableDartFiles:reachable.size,renderedAssets:rendered.size,removedAssets:0,classificationIsConservative:true,inventory,launcher:icons};
  fs.writeFileSync(path.join(root,'qa/source-audit/asset-inventory.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify({counts,renderedAssets:rendered.size,launcherDensities:icons.length,removedAssets:0}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
