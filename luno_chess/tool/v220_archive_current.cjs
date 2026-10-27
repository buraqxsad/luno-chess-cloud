const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const output = path.join(root, 'qa/v220/current');
const previous = JSON.parse(fs.readFileSync(path.join(root, 'qa/v219/after/render-manifest.json'), 'utf8'));
const lockPath = 'qa/v220/source-lock-first-full.json';
const lock = JSON.parse(fs.readFileSync(path.join(root, lockPath), 'utf8'));
const since = Date.parse(lock.recordedAt);
if (!Number.isFinite(since)) throw new Error('Missing final source freeze timestamp');
sharp.cache(false);

async function main() {
  fs.mkdirSync(path.join(output, 'screens'), {recursive: true});
  const rows = [];
  for (const old of previous.renders) {
    const source = path.resolve(root, old.source.replaceAll('\\', '/'));
    if (!source.startsWith(path.join(root, 'qa/rc/screens') + path.sep)) throw new Error('Unexpected render source');
    const stat = fs.statSync(source);
    if (stat.mtimeMs < since) throw new Error(`Stale final render: ${old.file}`);
    const bytes = fs.readFileSync(source);
    const metadata = await sharp(bytes).metadata();
    const stats = await sharp(bytes).stats();
    if (metadata.width !== old.width || metadata.height !== old.height ||
        stats.channels.every(channel => channel.stdev < 0.01)) throw new Error(`Invalid final render: ${old.file}`);
    const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
    fs.copyFileSync(source, path.join(output, 'screens', old.file));
    rows.push({file: old.file, width: metadata.width, height: metadata.height,
      sha256, previousSha256: old.sha256, identicalToV219: sha256 === old.sha256,
      source: path.relative(root, source).replaceAll('\\', '/'), modifiedAt: stat.mtime.toISOString()});
  }
  const selected = rows.filter(row => /^(home|play|shop|profile|friends|settings|collection|deck|loading|tutorial|premium)-(en|tr)\.png$/.test(row.file));
  if (selected.length !== 22) throw new Error('Expected 22 current main-screen contact frames');
  fs.mkdirSync(path.join(output, 'contacts'), {recursive: true});
  for (let start = 0; start < selected.length; start += 6) {
    const cells = selected.slice(start, start + 6);
    const width = 260, height = 590;
    const layers = [];
    for (let index = 0; index < cells.length; index++) {
      const row = cells[index];
      const input = await sharp(path.join(output, 'screens', row.file)).resize(width, height - 30, {fit: 'contain'}).png().toBuffer();
      const label = Buffer.from(`<svg width="260" height="30" xmlns="http://www.w3.org/2000/svg"><text x="6" y="20" fill="white" font-family="Arial" font-size="12">${row.file}</text></svg>`);
      layers.push({input, left: index % 3 * width, top: Math.floor(index / 3) * height + 30});
      layers.push({input: label, left: index % 3 * width, top: Math.floor(index / 3) * height});
    }
    await sharp({create: {width: width * 3, height: height * 2, channels: 4, background: '#10151c'}})
      .composite(layers).png().toFile(path.join(output, 'contacts', `main-${start / 6 + 1}.png`));
  }
  const result = {method: 'Fresh actual Flutter fixture renders after final V220 source freeze; not physical Android screenshots',
    sourceLock: lockPath, since: lock.recordedAt,
    renders: rows, unchangedPNGs: rows.filter(row => row.identicalToV219).length,
    selectedContactFrames: selected.map(row => row.file)};
  fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({renders: rows.length, unchangedPNGs: result.unchangedPNGs, selectedContactFrames: selected.length}));
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
