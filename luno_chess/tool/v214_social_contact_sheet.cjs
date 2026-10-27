const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '../qa/v214');
async function main() {
  const group = ['intro', 'deck', 'first'].includes(process.argv[2]) ? process.argv[2] : 'social';
  const files = fs.readdirSync(path.join(root, 'visual'))
    .filter(name => name.endsWith('.png') && (group === 'social'
      ? !name.startsWith('intro-') && !name.startsWith('deck-') && !name.startsWith('first-')
      : name.startsWith(group + '-'))).sort();
  const width = 300, height = 560, columns = 4;
  const layers = [];
  for (let index = 0; index < files.length; index++) {
    const png = await sharp(path.join(root, 'visual', files[index]))
      .resize(width, height - 30, {fit: 'contain', background: '#101820'}).png().toBuffer();
    const label = Buffer.from(`<svg width="${width}" height="30"><rect width="100%" height="100%" fill="#fff"/><text x="7" y="20" font-family="Arial" font-size="12" fill="#111">${files[index]}</text></svg>`);
    const left = index % columns * width, top = Math.floor(index / columns) * height;
    layers.push({input: label, left, top}, {input: png, left, top: top + 30});
  }
  await sharp({create: {width: columns * width, height: Math.ceil(files.length / columns) * height, channels: 4, background: '#101820'}})
    .composite(layers).png().toFile(path.join(root, `${group}-visual-sheet.png`));
  console.log(`Built sheet from ${files.length} actual widget-rendered captures.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
