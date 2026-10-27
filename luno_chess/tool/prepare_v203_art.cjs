const fs = require('fs'), path = require('path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'design/v203/source');
const assets = path.join(root, 'assets/native_art');
const generated = 'C:/Users/Casper/.codex/generated_images/019f5d34-6fc3-71e1-b469-b9e0da8eb51c';
const inputs = { panels: 'exec-28c8a38f-d8d3-4ebd-bd9b-13ca5e611f35.png', buttons: 'exec-61397eb8-f7ad-4a98-a3b0-6eb17d5af169.png', effects: 'exec-e32dbdb9-ebdf-4788-8696-8d7e4f44f928.png' };
const definitions = [
  ['panel-neutral', 'panels', 23, 87, 734, 398, 512, 288],
  ['panel-premium', 'panels', 780, 76, 737, 410, 512, 288],
  ['panel-collection', 'panels', 23, 526, 734, 400, 512, 288],
  ['panel-path', 'panels', 780, 526, 737, 400, 512, 288],
  ['button-primary', 'buttons', 22, 216, 478, 175, 512, 128],
  ['button-secondary', 'buttons', 533, 216, 478, 175, 512, 128],
  ['button-danger', 'buttons', 1042, 216, 478, 175, 512, 128],
  ['button-disabled', 'buttons', 22, 624, 478, 177, 512, 128],
  ['tab-selected', 'buttons', 533, 624, 478, 177, 512, 128],
  ['tab-inactive', 'buttons', 1042, 624, 478, 177, 512, 128],
];
(async () => {
  fs.mkdirSync(source, { recursive: true });
  for (const [name, file] of Object.entries(inputs)) fs.copyFileSync(path.join(generated, file), path.join(source, `${name}.png`));
  for (const [name, group, left, top, width, height, outWidth, outHeight] of definitions) {
    await sharp(path.join(source, `${group}.png`)).extract({ left, top, width, height }).resize(outWidth, outHeight).webp({ quality: 90, alphaQuality: 100, effort: 5 }).toFile(path.join(assets, `polish-v203-${name}.webp`));
  }
  const effectMetadata = await sharp(path.join(source, 'effects.png')).metadata();
  const cell = Math.floor(Math.min(effectMetadata.width, effectMetadata.height) / 2);
  for (const [i, name] of ['cast', 'reward', 'cleanse', 'impact'].entries()) {
    await sharp(path.join(source, 'effects.png')).extract({ left: (i % 2) * cell, top: Math.floor(i / 2) * cell, width: cell, height: cell }).resize(240, 240).extend({ top: 8, bottom: 8, left: 8, right: 8, background: '#00000000' }).webp({ quality: 90, alphaQuality: 100, effort: 5 }).toFile(path.join(assets, `polish-v203-${name}.webp`));
  }
  const files = fs.readdirSync(assets).filter(f => f.startsWith('polish-v203-'));
  const report = { files, bytes: files.reduce((n, file) => n + fs.statSync(path.join(assets, file)).size, 0), sources: inputs };
  fs.writeFileSync(path.join(root, 'qa/v203-assets.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ assets: files.length, bytes: report.bytes }));
})();
