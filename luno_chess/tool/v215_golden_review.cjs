const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'qa/v215/golden-review');
async function main() {
  fs.mkdirSync(output, {recursive: true});
  for (const [group, directory] of [
    ['battle', 'test/battle_ui/failures'],
    ['surfaces', 'test/failures'],
  ]) {
    const folder = path.join(root, directory);
    const names = fs.readdirSync(folder).filter(name => name.endsWith('_testImage.png'))
      .map(name => name.replace('_testImage.png', '')).sort();
    for (let start = 0; start < names.length; start += 4) {
      const page = names.slice(start, start + 4), composite = [];
      for (let row = 0; row < page.length; row++) {
        const name = page[row];
        for (const [column, suffix] of ['masterImage', 'testImage'].entries()) {
          const tile = await sharp(path.join(folder, `${name}_${suffix}.png`))
            .resize(390, 844, {fit: 'contain', background: '#070e17'}).png().toBuffer();
          const label = Buffer.from(`<svg width="390" height="24"><rect width="390" height="24" fill="#070e17"/><text x="8" y="18" font-family="Arial" font-size="14" fill="white">${name}: ${column ? 'V215' : 'baseline'}</text></svg>`);
          composite.push({input: label, left: column * 390, top: row * 868},
            {input: tile, left: column * 390, top: row * 868 + 24});
        }
      }
      await sharp({create: {width: 780, height: page.length * 868,
        channels: 4, background: '#070e17'}}).composite(composite).png()
        .toFile(path.join(output, `${group}-${start / 4 + 1}.png`));
    }
    fs.writeFileSync(path.join(output, `${group}-manifest.json`), JSON.stringify(names, null, 2));
  }
}
main().catch(error => {console.error(error); process.exitCode = 1;});
