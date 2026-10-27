const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const group = process.argv[2] || 'all';
const folder = path.resolve(__dirname, group === 'golden' ? '../test/failures' : '../qa/rc/screens');
const output = path.resolve(__dirname, group === 'golden' ? '../qa/rc/golden-review' : '../qa/rc/screens');
const groups = {
  all: () => true,
  battle: f => f.startsWith('battle-'),
  phone: f => !f.startsWith('battle-') && !f.startsWith('tutorial-step-') && /-(tr|en)\.png$/.test(f),
  compact: f => !f.startsWith('battle-') && f.endsWith('-compact.png'),
  scaled: f => !f.startsWith('battle-') && f.endsWith('-scaled.png'),
  tablet: f => !f.startsWith('battle-') && f.endsWith('-tablet.png'),
  landscape: f => !f.startsWith('battle-') && f.endsWith('-landscape.png'),
  tail: f => f.endsWith('-tail.png'),
  tutorial: f => f.startsWith('tutorial-step-'),
  golden: f => /^(home|pass|season|tutorial(?:-[1-9])?|achievements|browser|friends|missions|ranking|settings)_testImage\.png$/.test(f),
};
if (!groups[group]) throw new Error(`Unknown render group: ${group}`);
const files = fs.readdirSync(folder).filter(f => f.endsWith('.png') && !f.includes('contact-') && groups[group](f)).sort();
async function main() {
  fs.mkdirSync(output, {recursive: true});
  const summary = [];
  for (let start = 0; start < files.length; start += 6) {
    const composite = [];
    for (const [i, file] of files.slice(start, start + 6).entries()) {
      const name = file.slice(0, -4);
      const source = sharp(path.join(folder, file));
      const metadata = await source.metadata();
      const stats = await source.stats();
      if (metadata.width < (group === 'golden' ? 300 : 500) || metadata.height < 500 || stats.channels.every(c => c.stdev < 1)) {
        throw new Error(`Invalid or blank Flutter render: ${file}`);
      }
      summary.push({name, width: metadata.width, height: metadata.height});
      const tile = await source.resize(312, 675, {fit: 'contain', background: '#080f18'}).png().toBuffer();
      const label = Buffer.from(`<svg width="312" height="28"><rect width="312" height="28" fill="#080f18"/><text x="8" y="19" font-family="Arial" font-size="13" fill="#f3efe5">${name}</text></svg>`);
      composite.push({input: label, left: (i % 3) * 312, top: Math.floor(i / 3) * 703});
      composite.push({input: tile, left: (i % 3) * 312, top: Math.floor(i / 3) * 703 + 28});
    }
    await sharp({create: {width: 936, height: 1406, channels: 4, background: '#080f18'}})
      .composite(composite).png().toFile(path.join(output, `${group}-contact-${String(start / 6 + 1).padStart(2, '0')}.png`));
  }
  fs.writeFileSync(path.join(output, `${group}-render-matrix.json`), JSON.stringify(summary, null, 2));
  console.log(`${group}: ${files.length} actual Flutter renders; ${Math.ceil(files.length / 6)} contact sheets.`);
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
