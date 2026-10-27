const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const output = path.join(root, 'qa/v216/v203-golden-review');
const reference = path.join(root, 'qa/v203-after');
const mode = process.argv[2];
const names = [
  'home', 'shop', 'collection', 'cards', 'costumes', 'emojis', 'deck',
  'tutorial-1', 'tutorial-2', 'tutorial-3', 'tutorial-4', 'tutorial-5',
  'tutorial-6', 'tutorial-7', 'premium', 'arenas', 'play', 'friendly',
  'daily-reward', 'chest',
];
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

async function main() {
  if (!['archive', 'review', 'review-updated'].includes(mode)) {
    throw Error('Use archive, review or review-updated');
  }
  fs.mkdirSync(output, {recursive: true});
  const manifest = [];
  for (const name of names) {
    const oldFile = path.join(output, 'before', `${name}.png`);
    if (mode === 'archive') {
      const bytes = fs.readFileSync(path.join(reference, `${name}.png`));
      fs.mkdirSync(path.dirname(oldFile), {recursive: true});
      if (fs.existsSync(oldFile) && !fs.readFileSync(oldFile).equals(bytes)) {
        throw Error(`Refusing to overwrite old reference: ${name}`);
      }
      fs.writeFileSync(oldFile, bytes);
      manifest.push({name, bytes: bytes.length, sha256: digest(bytes)});
      continue;
    }
    const afterFile = mode === 'review-updated'
      ? path.join(reference, `${name}.png`)
      : path.join(root, 'test/failures', `${name}_testImage.png`);
    const oldBytes = fs.readFileSync(oldFile);
    const newBytes = fs.readFileSync(afterFile);
    const afterArchive = path.join(output, 'after', `${name}.png`);
    fs.mkdirSync(path.dirname(afterArchive), {recursive: true});
    fs.writeFileSync(afterArchive, newBytes);
    manifest.push({name, beforeSha256: digest(oldBytes),
      afterSha256: digest(newBytes), currentSource: path.relative(root, afterFile)});
    const tiles = [];
    for (const [column, bytes] of [oldBytes, newBytes].entries()) {
      const input = await sharp(bytes).resize(390, 844, {
        fit: 'contain', background: '#17212b',
      }).png().toBuffer();
      const label = Buffer.from(`<svg width="390" height="24"><rect width="390" height="24" fill="#17212b"/><text x="8" y="18" font-family="Arial" font-size="14" fill="white">${name}: ${column ? 'V216 actual' : 'previous V203 reference'}</text></svg>`);
      tiles.push({input: label, left: column * 390, top: 0},
        {input, left: column * 390, top: 24});
    }
    await sharp({create: {width: 780, height: 868, channels: 4,
      background: '#17212b'}}).composite(tiles).png()
      .toFile(path.join(output, `${name}.png`));
  }
  fs.writeFileSync(path.join(output, mode === 'archive'
    ? 'before-manifest.json' : 'review-manifest.json'),
  JSON.stringify(manifest, null, 2));
  console.log(`${mode}: ${manifest.length} V203 surface references.`);
}

main().catch(error => {console.error(error); process.exitCode = 1;});
