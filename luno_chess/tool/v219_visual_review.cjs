const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const phase = process.argv[2];
if (!['before', 'after'].includes(phase)) throw Error('Use before or after');
const lock = JSON.parse(fs.readFileSync(path.resolve(root,
  process.argv[3] || 'qa/v219/source-lock-before.json'), 'utf8'));
const since = Date.parse(lock.recordedAt) - 1000;
const source = path.join(root, 'qa/rc/screens');
const destination = path.join(root, 'qa/v219', phase, 'screens');
const contacts = path.join(root, 'qa/v219', phase, 'contacts');
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

async function main() {
  fs.mkdirSync(destination, {recursive: true});
  fs.mkdirSync(contacts, {recursive: true});
  const files = fs.readdirSync(source).filter(file => file.endsWith('.png') &&
    !file.includes('contact-') && fs.statSync(path.join(source, file)).mtimeMs >= since).sort();
  const manifest = [];
  for (const file of files) {
    const bytes = fs.readFileSync(path.join(source, file));
    const image = sharp(bytes), meta = await image.metadata(), stats = await image.stats();
    if (!meta.width || !meta.height || stats.channels.every(c => c.stdev < 1)) {
      throw Error(`Blank/invalid actual render: ${file}`);
    }
    const output = path.join(destination, file);
    fs.writeFileSync(output, bytes);
    const metadata = path.join(source, file.replace(/\.png$/, '.json'));
    if (fs.existsSync(metadata)) fs.copyFileSync(metadata,
      path.join(destination, path.basename(metadata)));
    manifest.push({file, width: meta.width, height: meta.height,
      sha256: digest(bytes), source: path.relative(root, path.join(source, file)),
      modifiedAt: fs.statSync(path.join(source, file)).mtime.toISOString()});
  }
  const groups = {
    tr: f => !f.startsWith('battle-') && !f.startsWith('tutorial-step-') && /-tr\.png$/.test(f),
    en: f => !f.startsWith('battle-') && !f.startsWith('tutorial-step-') && /-en\.png$/.test(f),
    battle: f => f.startsWith('battle-') &&
      /(?:battle-(?:main|selected|target|victory|defeat|draw|reconnect|error|compact)|card-(?:mine|freeze|prophecy|break_seal))/.test(f),
    compact: f => f.endsWith('-compact.png'),
    scaled: f => f.endsWith('-scaled.png'),
    tablet: f => f.endsWith('-tablet.png'),
    landscape: f => f.endsWith('-landscape.png'),
  };
  const sheets = [];
  for (const [group, accept] of Object.entries(groups)) {
    const selected = files.filter(accept);
    for (let start = 0; start < selected.length; start += 6) {
      const tiles = [];
      for (const [index, file] of selected.slice(start, start + 6).entries()) {
        const left = index % 3 * 312, top = Math.floor(index / 3) * 703;
        const label = Buffer.from(`<svg width="312" height="28"><rect width="312" height="28" fill="#080f18"/><text x="6" y="19" font-family="Arial" font-size="12" fill="white">${file}</text></svg>`);
        const tile = await sharp(path.join(destination, file)).resize(312, 675,
          {fit: 'contain', background: '#080f18'}).png().toBuffer();
        tiles.push({input: label, left, top}, {input: tile, left, top: top + 28});
      }
      const name = `${group}-${String(start / 6 + 1).padStart(2, '0')}.png`;
      await sharp({create: {width: 936, height: 1406, channels: 4,
        background: '#080f18'}}).composite(tiles).png().toFile(path.join(contacts, name));
      sheets.push({file: name, renders: selected.slice(start, start + 6)});
    }
  }
  fs.writeFileSync(path.join(root, 'qa/v219', phase, 'render-manifest.json'),
    JSON.stringify({method: 'Actual Flutter fixture PNGs, timestamp-gated to this source pass; not device/live-online evidence',
      since: new Date(since).toISOString(), renders: manifest, contacts: sheets}, null, 2));
  console.log(JSON.stringify({phase, renders: files.length, contactSheets: sheets.length}));
}
main().catch(error => {console.error(error); process.exitCode = 1;});
