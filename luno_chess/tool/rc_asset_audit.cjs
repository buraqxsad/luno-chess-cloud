const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const inventory = JSON.parse(fs.readFileSync(path.join(root, 'qa/rc/product-inventory.json'), 'utf8'));
const sources = inventory.reachableFiles.map(file => [file, fs.readFileSync(path.join(root, file), 'utf8')]);
const metadata = fs.readdirSync(path.join(root, 'qa/rc/screens')).filter(f => f.endsWith('.json') && !f.includes('render-matrix'));
const renders = new Map();
for (const file of metadata) {
  const record = JSON.parse(fs.readFileSync(path.join(root, 'qa/rc/screens', file), 'utf8'));
  for (const asset of record.assets || []) {
    if (!renders.has(asset)) renders.set(asset, []);
    renders.get(asset).push(record.name);
  }
}
async function main() {
  const rows = [];
  const hashes = new Map();
  for (const asset of inventory.assets) {
    const buffer = fs.readFileSync(path.join(root, asset.file));
    const sha256 = crypto.createHash('sha256').update(buffer).digest('hex');
    if (!hashes.has(sha256)) hashes.set(sha256, []);
    hashes.get(sha256).push(asset.file);
    const directReferences = sources.filter(([, source]) => source.includes(asset.file) || source.includes(path.posix.basename(asset.file))).map(([file]) => file);
    const row = {...asset, sha256, directReferences, renderedIn: renders.get(asset.file) || []};
    row.evidence = row.renderedIn.length ? 'RENDERED_FIXTURE' : directReferences.length ? 'STATIC_REFERENCE' : 'NO_DIRECT_REFERENCE_DYNAMIC_USE_NOT_EXCLUDED';
    if (/\.(png|webp|jpg|jpeg|gif)$/.test(asset.file)) {
      const image = sharp(buffer);
      const details = await image.metadata();
      row.image = {format: details.format, width: details.width, height: details.height, pages: details.pages || 1};
      await image.stats();
      if (!details.width || !details.height) throw new Error(`Invalid image: ${asset.file}`);
    }
    rows.push(row);
  }
  const duplicateGroups = [...hashes.values()].filter(files => files.length > 1);
  const result = {
    method: 'SHA-256 exact duplicates, first-page image decoding, conservative direct references and actual render metadata; non-image files are hashed, not decoder-validated; not visual approval or proof of dynamic unreachability',
    assets: rows.length,
    totalBytes: rows.reduce((sum, r) => sum + r.bytes, 0),
    renderedAssets: rows.filter(r => r.renderedIn.length).length,
    duplicateGroups,
    removedAssets: 0,
    inventory: rows,
  };
  fs.writeFileSync(path.join(root, 'qa/rc/asset-audit.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({assets: result.assets, bytes: result.totalBytes, renderedAssets: result.renderedAssets, duplicateGroups: duplicateGroups.length, removedAssets: 0}));
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
