const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const candidates = [
  'shop-costume-showcase-v1.png', 'missions-scene-v27.png', 'shop-surface-v26.png',
  'phase2/gameplay-atmosphere-v2.png', 'phase2/tutorial-academy-v2.png', 'phase2/result-victory-v2.png',
  'achievements-scene-v34.png', 'phase2/ranking-podium-v2.png', 'gameplay-scene-v28.png',
  'phase2/shop-showcase-v2.png',
];
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
async function main() {
  const records = [];
  const apply = process.argv.includes('--apply');
  for (const asset of candidates) {
    const filename = path.join(root, 'assets/native_art', asset);
    const source = fs.readFileSync(filename);
    const optimized = await sharp(source).png({compressionLevel: 9, effort: 10, adaptiveFiltering: true, palette: false}).toBuffer();
    const before = await sharp(source).ensureAlpha().raw().toBuffer();
    const after = await sharp(optimized).ensureAlpha().raw().toBuffer();
    if (!before.equals(after)) throw Error(`Decoded pixels differ: ${asset}`);
    const saved = source.length - optimized.length;
    const record = {asset, beforeBytes: source.length, afterBytes: optimized.length, savedBytes: saved,
      beforeHash: hash(source), optimizedHash: hash(optimized), decodedPixelHash: hash(before), applied: apply && saved > 65536};
    if (record.applied) {
      // Recheck bytes immediately before replacement to respect parallel work.
      if (hash(fs.readFileSync(filename)) !== record.beforeHash) throw Error(`Source changed: ${asset}`);
      const backup = path.join(root, 'qa/v215/assets/lossless-originals', asset);
      fs.mkdirSync(path.dirname(backup), {recursive: true});
      fs.writeFileSync(backup, source);
      fs.writeFileSync(filename, optimized);
    }
    records.push(record);
  }
  fs.writeFileSync(path.join(root, `qa/v215/assets/lossless-${apply ? 'applied' : 'dry-run'}.json`), JSON.stringify(records, null, 2));
  console.log(JSON.stringify({applied: records.filter(record => record.applied).length, potentialSavings: records.reduce((sum, r) => sum + Math.max(0, r.savedBytes), 0), records}));
}
main().catch(error => {console.error(error); process.exitCode = 1;});
