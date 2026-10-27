const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const phase = process.argv[2] || 'after';
const root = path.resolve(__dirname, '../qa/v216', phase, 'tutorial-home');
async function main() {
  const names = fs.readdirSync(root).filter(name => name.endsWith('.png') && !name.startsWith('sheet-')).sort();
  const records = [];
  for (let offset = 0; offset < names.length; offset += 12) {
    const tiles = [];
    for (const [i, name] of names.slice(offset, offset + 12).entries()) {
      const source = path.join(root, name);
      const stats = await sharp(source).stats();
      if (stats.channels.slice(0, 3).every(c => c.stdev < 1)) throw Error(`Blank: ${name}`);
      const metadata = await sharp(source).metadata();
      records.push({name, width: metadata.width, height: metadata.height, nonblank: true});
      tiles.push({input: await sharp(source).resize({width: 240, height: 520, fit: 'contain', background: '#20272b'}).png().toBuffer(), left: i % 4 * 240, top: Math.floor(i / 4) * 550 + 30});
      const label = Buffer.from(`<svg width="240" height="30" xmlns="http://www.w3.org/2000/svg"><text x="4" y="19" fill="white" font-family="Arial" font-size="9">${name}</text></svg>`);
      tiles.push({input: label, left: i % 4 * 240, top: Math.floor(i / 4) * 550});
    }
    await sharp({create: {width: 960, height: 1650, channels: 4, background: '#20272b'}}).composite(tiles).png().toFile(path.join(root, `sheet-${offset / 12 + 1}.png`));
  }
  fs.writeFileSync(path.join(root, 'pixel-audit.json'), JSON.stringify(records, null, 2));
  const sourceFiles = [
    'lib/screens/battle_introduction_screen.dart',
    'lib/widgets/battle_lesson_stage.dart',
    'lib/screens/home_screen.dart',
    'lib/widgets/tutorial_coach.dart',
    'lib/theme/luno_theme.dart',
    'test/v216_tutorial_home_regression_test.dart',
    'test/v216_tutorial_home_visual_test.dart',
    'pubspec.yaml',
    'assets/fonts/nunito/nunito-variable.ttf',
    'assets/fonts/cinzel-latin.ttf',
    'assets/fonts/cinzel-turkish.ttf',
  ];
  fs.writeFileSync(path.join(root, 'source-manifest.json'), JSON.stringify({
    phase,
    generatedAt: new Date().toISOString(),
    captures: records.length,
    sourceFiles: sourceFiles.map(name => ({
      name,
      sha256: crypto.createHash('sha256').update(fs.readFileSync(path.resolve(__dirname, '..', name))).digest('hex'),
    })),
  }, null, 2));
  let comparisons = 0;
  if (phase === 'after') {
    const before = path.resolve(__dirname, '../qa/v216/before/tutorial-home');
    const comparisonRoot = path.resolve(__dirname, '../qa/v216/tutorial-home-comparisons');
    fs.mkdirSync(comparisonRoot, {recursive: true});
    const surfaces = ['intro-mana-', 'intro-mineConfirm-', 'intro-victory-', 'academy-3-', 'academy-7-', 'home-'];
    for (const name of names.filter(name => surfaces.some(surface => name.startsWith(surface)) && fs.existsSync(path.join(before, name)))) {
      const {width, height} = await sharp(path.join(root, name)).metadata();
      const label = Buffer.from(`<svg width="${width * 2}" height="30" xmlns="http://www.w3.org/2000/svg"><text x="8" y="20" fill="white" font-family="Arial" font-size="14">BEFORE</text><text x="${width + 8}" y="20" fill="white" font-family="Arial" font-size="14">AFTER</text></svg>`);
      await sharp({create: {width: width * 2, height: height + 30, channels: 4, background: '#20272b'}}).composite([
        {input: label, left: 0, top: 0},
        {input: path.join(before, name), left: 0, top: 30},
        {input: path.join(root, name), left: width, top: 30},
      ]).png().toFile(path.join(comparisonRoot, name));
      comparisons++;
    }
  }
  console.log(JSON.stringify({phase, captures: records.length, nonblank: records.length, comparisons}));
}
main().catch(error => {console.error(error); process.exitCode = 1;});
