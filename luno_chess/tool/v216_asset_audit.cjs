const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');

function files(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? files(file) : [file];
  });
}
const relative = file => path.relative(root, file).replaceAll('\\', '/');

async function main() {
  const entries = [];
  const failures = [];
  for (const file of files(path.join(root, 'assets'))) {
    const bytes = fs.readFileSync(file);
    const entry = {path: relative(file), bytes: bytes.length,
      sha256: crypto.createHash('sha256').update(bytes).digest('hex')};
    if (/\.(png|webp|jpg|jpeg|gif)$/i.test(file)) {
      try {
        const metadata = await sharp(bytes).metadata();
        const stats = await sharp(bytes).stats();
        entry.image = {width: metadata.width, height: metadata.height, format: metadata.format,
          alpha: metadata.hasAlpha, channels: stats.channels.map(channel => ({min: channel.min, max: channel.max, stdev: channel.stdev}))};
        if (!metadata.width || !metadata.height) throw Error('Image has no dimensions');
      } catch (error) {
        failures.push({path: entry.path, error: error.message});
      }
    }
    entries.push(entry);
  }
  const source = new Map(files(path.join(root, 'lib')).filter(file => file.endsWith('.dart'))
    .map(file => [relative(file), fs.readFileSync(file, 'utf8')]));
  const reachable = new Set();
  function visit(file) {
    if (reachable.has(file) || !source.has(file)) return;
    reachable.add(file);
    for (const match of source.get(file).matchAll(/(?:import|export)\s+['"]([^'"]+)['"]/g)) {
      const target = match[1];
      if (target.startsWith('package:luno_chess/')) visit(`lib/${target.slice('package:luno_chess/'.length)}`);
      else if (!target.includes(':')) visit(path.posix.normalize(path.posix.join(path.posix.dirname(file), target)));
    }
  }
  visit('lib/main.dart');
  const missingLiterals = [];
  for (const file of reachable) for (const match of source.get(file).matchAll(/['"](assets\/[^'"\r\n]+)['"]/g)) {
    const asset = match[1];
    if (!asset.includes('$') && /\.(png|webp|jpg|jpeg|gif|wav|ogg|mp3|ttf)$/i.test(asset) && !fs.existsSync(path.join(root, asset))) {
      missingLiterals.push({source: file, asset});
    }
  }
  const result = {createdAt: new Date().toISOString(), files: entries.length,
    decodedImages: entries.filter(entry => entry.image).length,
    bytes: entries.reduce((sum, entry) => sum + entry.bytes, 0),
    reachableDartFiles: reachable.size, failures, missingLiterals, entries,
    limits: 'Static asset decoding and conservative reachable literal checks, not package/runtime acceptance or proof for every dynamic path. No assets deleted.'};
  const output = path.resolve(root, process.env.LUNO_ASSET_AUDIT_DIR || 'qa/v216');
  fs.mkdirSync(output, {recursive: true});
  fs.writeFileSync(path.join(output, 'asset-audit.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify({files: result.files, decodedImages: result.decodedImages,
    bytes: result.bytes, failures, missingLiterals}));
  if (failures.length || missingLiterals.length) process.exitCode = 1;
}
main().catch(error => {console.error(error); process.exitCode = 1;});
