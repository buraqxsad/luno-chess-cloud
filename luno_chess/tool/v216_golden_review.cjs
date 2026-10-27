const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const output = path.join(root, 'qa/v216/golden-review');
const reference = path.join(root, 'test/battle_ui/goldens');
const mode = process.argv[2];
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

async function main() {
  fs.mkdirSync(output, {recursive: true});
  if (mode === 'archive') {
    const archive = path.join(output, 'before');
    fs.mkdirSync(archive, {recursive: true});
    const manifest = [];
    for (const name of fs.readdirSync(reference).filter(name => name.endsWith('.png')).sort()) {
      const bytes = fs.readFileSync(path.join(reference, name));
      const destination = path.join(archive, name);
      if (fs.existsSync(destination) && !fs.readFileSync(destination).equals(bytes)) {
        throw Error(`Refusing to overwrite preserved reference: ${name}`);
      }
      fs.writeFileSync(destination, bytes);
      manifest.push({name, bytes: bytes.length, sha256: digest(bytes)});
    }
    fs.writeFileSync(path.join(output, 'before-manifest.json'), JSON.stringify(manifest, null, 2));
    console.log(`Preserved ${manifest.length} existing golden references.`);
    return;
  }
  if (!['review', 'review-updated'].includes(mode)) {
    throw Error('Use archive, review or review-updated');
  }
  const failures = path.join(root, 'test/battle_ui/failures');
  const updated = mode === 'review-updated';
  const names = updated
    ? fs.readdirSync(reference).filter(name => name.endsWith('.png'))
      .map(name => name.slice(0, -4)).sort()
    : fs.readdirSync(failures).filter(name => name.endsWith('_testImage.png'))
      .map(name => name.replace('_testImage.png', '')).sort();
  const manifest = [];
  for (let start = 0; start < names.length; start += 4) {
    const composite = [];
    const page = names.slice(start, start + 4);
    for (const [row, name] of page.entries()) {
      const before = path.join(output, 'before', `${name}.png`);
      const after = updated ? path.join(reference, `${name}.png`)
        : path.join(failures, `${name}_testImage.png`);
      const afterBytes = fs.readFileSync(after);
      const archive = path.join(output, 'after', `${name}.png`);
      fs.mkdirSync(path.dirname(archive), {recursive: true});
      fs.writeFileSync(archive, afterBytes);
      manifest.push({name, beforeSha256: digest(fs.readFileSync(before)),
        afterSha256: digest(afterBytes), sheetsAreScaledThumbnails: true});
      for (const [column, file] of [before, after].entries()) {
        const tile = await sharp(file).resize(390, 844, {
          fit: 'contain', background: '#17212b',
        }).png().toBuffer();
        const label = Buffer.from(`<svg width="390" height="24"><rect width="390" height="24" fill="#17212b"/><text x="8" y="18" font-family="Arial" font-size="14" fill="white">${name}: ${column ? 'V216 actual' : 'previous reference'}</text></svg>`);
        composite.push({input: label, left: column * 390, top: row * 868},
          {input: tile, left: column * 390, top: row * 868 + 24});
      }
    }
    await sharp({create: {width: 780, height: page.length * 868,
      channels: 4, background: '#17212b'}}).composite(composite).png()
      .toFile(path.join(output, `battle-${start / 4 + 1}.png`));
  }
  fs.writeFileSync(path.join(output, 'review-manifest.json'), JSON.stringify(manifest, null, 2));
  console.log(`Composited ${names.length} real before/after golden pairs.`);
}

main().catch(error => {console.error(error); process.exitCode = 1;});
