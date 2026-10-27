const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const stage = process.argv[2] || 'after';
const directory = path.join(root, 'qa/v215', stage);
const out = path.join(root, 'qa/v215', `${stage}-sheets`);
async function main() {
  fs.mkdirSync(out, {recursive: true});
  const records = [];
  for (const prefix of ['shop', 'pass', 'premium', 'costumes', 'battle-board']) {
    const names = fs.readdirSync(directory).filter(name => name.startsWith(`${prefix}-`) && name.endsWith('.png')).sort();
    for (let offset = 0; offset < names.length; offset += 6) {
      const group = names.slice(offset, offset + 6);
      const tiles = [];
      for (let i = 0; i < group.length; i++) {
        const name = group[i];
        const source = path.join(directory, name);
        const pixels = await sharp(source).stats();
        if (pixels.channels.slice(0, 3).every(channel => channel.stdev < 1)) throw Error(`Blank render: ${name}`);
        const image = await sharp(source).resize({width: 270, height: 580, fit: 'contain', background: '#252a30'}).png().toBuffer();
        const label = Buffer.from(`<svg width="270" height="30" xmlns="http://www.w3.org/2000/svg"><text x="4" y="20" fill="white" font-family="Arial" font-size="11">${name}</text></svg>`);
        tiles.push({input: image, left: i % 3 * 270, top: Math.floor(i / 3) * 610 + 30},
          {input: label, left: i % 3 * 270, top: Math.floor(i / 3) * 610});
        const metadata = JSON.parse(fs.readFileSync(source.replace(/\.png$/, '.json'), 'utf8'));
        records.push({name, nonblank: true, scale: metadata.scaleAt14, ellipsized: metadata.ellipsized});
      }
      await sharp({create: {width: 810, height: 1220, channels: 4, background: '#252a30'}})
        .composite(tiles).png().toFile(path.join(out, `${prefix}-${Math.floor(offset / 6) + 1}.png`));
    }
  }
  fs.writeFileSync(path.join(out, 'pixel-audit.json'), JSON.stringify(records, null, 2));
  console.log(JSON.stringify({stage, captures: records.length, ellipsized: records.filter(record => record.ellipsized.length > 0)}));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
