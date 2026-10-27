const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const stage = process.argv[2];
if (!['before', 'after'].includes(stage)) throw Error('Use before or after');
const source = path.join(root, 'qa/v216', stage === 'before' ? 'inventory/general' : 'after/general');
const out = path.join(root, `qa/v216/${stage}/general-sheets`);
const widths = [320, 390, 430, 768];
const surfaces = [
  'loading', 'username', 'play', 'difficulty', 'friendly', 'online', 'shop', 'pass',
  'premium', 'profile', 'history', 'achievements', 'edit-profile', 'public-profile',
  'ranking', 'season', 'missions', 'friends', 'inbox', 'dm', 'levels', 'settings',
];
if (stage === 'after') surfaces.push('inbox-populated', 'inbox-empty');

async function main() {
  fs.mkdirSync(out, {recursive: true});
  const records = [];
  for (const surface of surfaces) {
    const tiles = [];
    for (let row = 0; row < 2; row++) for (let col = 0; col < widths.length; col++) {
      const language = row === 0 ? 'tr' : 'en';
      const name = `${surface}-${language}-${widths[col]}`;
      const file = path.join(source, `${name}.png`);
      let metadata;
      let metadataError;
      try {
        metadata = JSON.parse(fs.readFileSync(path.join(source, `${name}.json`), 'utf8'));
      } catch (error) {
        if (stage === 'after') throw Error(`Invalid current capture metadata: ${name}: ${error.message}`);
        metadataError = error.message;
      }
      let sample;
      try {
        sample = await sharp(file).resize(64, 64).removeAlpha().raw().toBuffer();
      } catch (error) {
        if (stage === 'after') throw Error(`Invalid current capture image: ${name}: ${error.message}`);
        records.push({name, imageError: error.message, metadataError});
        const input = Buffer.from(`<svg width="180" height="340"><rect width="180" height="340" fill="#253443"/><text x="8" y="30" fill="#ffffff" font-family="Arial" font-size="12">Missing interrupted evidence</text><text x="8" y="52" fill="#ffffff" font-family="Arial" font-size="12">${name}</text></svg>`);
        tiles.push({input, left: col * 192 + 6, top: row * 376 + 30});
        continue;
      }
      const mean = sample.reduce((sum, byte) => sum + byte, 0) / sample.length;
      const variance = sample.reduce((sum, byte) => sum + (byte - mean) ** 2, 0) / sample.length;
      if (variance < 20) throw Error(`Blank or near-blank capture: ${name}`);
      records.push({name, variance, assets: metadata?.assets, viewport: metadata?.logicalViewport,
        textScale: metadata?.textScaleAt14, ellipsizedText: metadata?.ellipsizedText,
        metadataError});
      const input = await sharp(file).resize(180, 340, {fit: 'contain', background: '#253443'}).png().toBuffer();
      const label = Buffer.from(`<svg width="180" height="22"><rect width="180" height="22" fill="#253443"/><text x="4" y="16" fill="#ffffff" font-family="Arial" font-size="13">${language} / ${widths[col]} / 150%</text></svg>`);
      tiles.push({input: label, left: col * 192 + 6, top: row * 376 + 6});
      tiles.push({input, left: col * 192 + 6, top: row * 376 + 30});
    }
    await sharp({create: {width: 768, height: 752, channels: 4, background: '#253443'}})
      .composite(tiles).png().toFile(path.join(out, `${surface}.png`));
  }
  fs.writeFileSync(path.join(root, `qa/v216/general-pixels-${stage}.json`), JSON.stringify({
    stage, captures: records.filter(record => !record.imageError).length,
    requestedCaptures: records.length, surfaces: surfaces.length,
    contactSheetsAreThumbnails: true,
    missingImages: records.filter(record => record.imageError).map(record => record.name),
    missingMetadata: records.filter(record => record.metadataError).map(record => record.name),
    records,
  }, null, 2));
  console.log(JSON.stringify({stage, captures: records.filter(record => !record.imageError).length,
    missingImages: records.filter(record => record.imageError).length,
    missingMetadata: records.filter(record => record.metadataError).length, surfaces: surfaces.length, out}));
}

main().catch(error => {console.error(error); process.exitCode = 1;});
