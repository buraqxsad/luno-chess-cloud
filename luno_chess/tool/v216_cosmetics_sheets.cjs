const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '../qa/v216');
const stage = process.argv[2] || 'finish-after';
const input = path.join(root, stage, 'cosmetics-emotes');
const output = path.join(root, stage + '-sheets', 'cosmetics-emotes');
fs.mkdirSync(output, {recursive: true});
const label = (text, width) => Buffer.from(`<svg width="${width}" height="24" xmlns="http://www.w3.org/2000/svg"><text x="4" y="17" fill="white" font-family="Arial" font-size="12">${text}</text></svg>`);

async function main() {
  const records = [];
  for (const name of fs.readdirSync(input).filter(n => n.endsWith('.png'))) {
    const stats = await sharp(path.join(input, name)).stats();
    const metadata = await sharp(path.join(input, name)).metadata();
    if (stats.channels.slice(0, 3).every(c => c.stdev < 1)) throw Error(`Blank: ${name}`);
    records.push({name, width: metadata.width, height: metadata.height, nonblank: true});
  }
  for (const prefix of ['costumes', 'emotes', 'chest', 'costume-preview', 'costume-preview-2x', 'emote-preview', 'emote-detail', 'reward-card', 'reward-set']) {
    const names = records.map(r => r.name).filter(n => prefix === 'costume-preview-2x'
      ? n.startsWith('costume-preview-') && n.endsWith('-200.png')
      : n.startsWith(prefix + '-') && /-(tr|en)-\d+-150\.png$/.test(n)).sort();
    if (!names.length) continue;
    const tiles = [];
    for (let i = 0; i < names.length; i++) {
      const left = i % 4 * 215, top = Math.floor(i / 4) * 534;
      tiles.push({input: label(names[i], 215), left, top},
        {input: await sharp(path.join(input, names[i])).resize({width: 215, height: 510, fit: 'contain', background: '#11191d'}).png().toBuffer(), left, top: top + 24});
    }
    await sharp({create: {width: 860, height: Math.ceil(names.length / 4) * 534, channels: 4, background: '#11191d'}})
      .composite(tiles).png().toFile(path.join(output, prefix + '.png'));
    if (prefix === 'emote-detail' || prefix === 'chest') {
      for (let start = 0; start < names.length; start += 12) {
        const page = tiles.slice(start * 2, (start + 12) * 2)
          .map(tile => ({...tile, top: tile.top - Math.floor(start / 4) * 534}));
        await sharp({create: {width: 860, height: Math.ceil(Math.min(12, names.length - start) / 4) * 534,
          channels: 4, background: '#11191d'}}).composite(page).png()
          .toFile(path.join(output, `${prefix}-page-${start / 12 + 1}.png`));
      }
    }
  }
  const pieces = records.map(r => r.name).filter(n => n.startsWith('pieces-')).sort();
  if (pieces.length) {
    const tiles = [];
    for (let i = 0; i < pieces.length; i++) {
      const left = i % 3 * 430, top = Math.floor(i / 3) * 184;
      tiles.push({input: label(pieces[i], 430), left, top},
        {input: await sharp(path.join(input, pieces[i])).extract({left: 0, top: 120, width: 430, height: 160}).png().toBuffer(), left, top: top + 24});
    }
    await sharp({create: {width: 1290, height: Math.ceil(pieces.length / 3) * 184, channels: 4, background: '#11191d'}})
      .composite(tiles).png().toFile(path.join(output, 'all-piece-scales.png'));
  }
  const comparisons = path.join(root, stage + '-comparisons', 'cosmetics-emotes');
  const comparisonRecords = [];
  fs.mkdirSync(comparisons, {recursive: true});
  for (const name of records.map(r => r.name)) {
    const original = path.join(root, 'before', 'cosmetics-emotes', name);
    const recovery = path.join(root, 'recovery-before', 'cosmetics-emotes', name);
    const preFinish = path.join(root, 'recovery-after', 'cosmetics-emotes', name);
    const before = fs.existsSync(original) ? original : fs.existsSync(recovery) ? recovery : preFinish;
    if (!fs.existsSync(before)) continue;
    const metadata = await sharp(before).metadata();
    await sharp({create: {width: metadata.width * 2, height: metadata.height + 24, channels: 4, background: '#11191d'}})
      .composite([{input: label(before === original ? 'BEFORE' : before === recovery
          ? 'BEFORE (recovery checkpoint)' : 'BEFORE (pre-finish checkpoint)', metadata.width), left: 0, top: 0},
        {input: label('AFTER', metadata.width), left: metadata.width, top: 0},
        {input: before, left: 0, top: 24}, {input: path.join(input, name), left: metadata.width, top: 24}])
      .png().toFile(path.join(comparisons, name));
    comparisonRecords.push({name, before: path.relative(root, before), after: path.relative(root, path.join(input, name))});
  }
  fs.writeFileSync(path.join(comparisons, 'comparison-manifest.json'), JSON.stringify(comparisonRecords, null, 2));
  fs.writeFileSync(path.join(output, 'pixel-audit.json'), JSON.stringify(records, null, 2));
  console.log(JSON.stringify({stage, captures: records.length, comparisons: comparisonRecords.length, nonblank: true}));
}
main().catch(error => {console.error(error); process.exitCode = 1;});
