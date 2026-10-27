const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '../qa/v216');
async function main() {
  const records = [];
  for (const phase of ['before', 'after']) {
    const directory = path.join(root, phase, 'progression');
    const out = path.join(root, `${phase}-sheets`, 'progression');
    fs.mkdirSync(out, {recursive: true});
    for (const prefix of ['collection', 'collection-rest', 'arenas', 'arenas-progress', 'arenas-max', 'deck', 'deck-cards', 'cards', 'cards-locked', 'card-condition', 'card-owned', 'card-owned-action', 'deck-replace', 'deck-unsaved', 'deck-save-error', 'deck-saved', 'deck-session', 'deck-longnames', 'cards-offline']) {
      for (const scale of ['100', '150']) {
        const names = fs.readdirSync(directory).filter(name => new RegExp(`^${prefix}-(tr|en)-[0-9]+-text${scale}\\.png$`).test(name)).sort();
        if (!names.length) continue;
        const tiles = [];
        for (let i = 0; i < names.length; i++) {
          const source = path.join(directory, names[i]);
          const stats = await sharp(source).stats();
          const metadata = await sharp(source).metadata();
          if (stats.channels.slice(0, 3).every(channel => channel.stdev < 1)) throw Error(`Blank ${source}`);
          const image = await sharp(source).resize({width: 195, height: 466, fit: 'contain', background: '#14191d'}).png().toBuffer();
          const label = Buffer.from(`<svg width="195" height="24" xmlns="http://www.w3.org/2000/svg"><text x="4" y="16" fill="white" font-family="Arial" font-size="10">${names[i]}</text></svg>`);
          tiles.push({input: label, left: i % 4 * 195, top: Math.floor(i / 4) * 490},
            {input: image, left: i % 4 * 195, top: Math.floor(i / 4) * 490 + 24});
          records.push({phase, name: names[i], nonblank: true, width: metadata.width, height: metadata.height,
            sha256: crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex')});
        }
        const sheet = path.join(out, `${prefix}-text${scale}.png`);
        if (phase !== 'before' || !fs.existsSync(sheet)) {
          await sharp({create: {width: 780, height: Math.ceil(names.length / 4) * 490, channels: 4, background: '#14191d'}}).composite(tiles).png().toFile(sheet);
        }
      }
    }
  }
  const comparisons = path.join(root, 'comparisons', 'progression');
  fs.mkdirSync(comparisons, {recursive: true});
  for (const prefix of ['collection', 'arenas', 'deck', 'deck-cards', 'cards', 'cards-locked']) {
    for (const language of ['tr', 'en']) {
      for (const width of [320, 390, 430, 768]) {
        const name = `${prefix}-${language}-${width}-text150.png`;
        const before = path.join(root, 'before', 'progression', name);
        const after = path.join(root, 'after', 'progression', name);
        const metadata = await sharp(before).metadata();
        const label = Buffer.from(`<svg width="${width * 2}" height="28" xmlns="http://www.w3.org/2000/svg"><text x="8" y="19" fill="white" font-family="Arial" font-size="14">BEFORE</text><text x="${width + 8}" y="19" fill="white" font-family="Arial" font-size="14">AFTER</text></svg>`);
        await sharp({create: {width: width * 2, height: metadata.height + 28, channels: 4, background: '#14191d'}})
          .composite([{input: label, left: 0, top: 0}, {input: before, left: 0, top: 28}, {input: after, left: width, top: 28}])
          .png().toFile(path.join(comparisons, name));
      }
    }
  }
  fs.writeFileSync(path.join(root, 'progression-pixel-audit.json'), JSON.stringify(records, null, 2));
  const files = [
    'lib/screens/battle_deck_screen.dart',
    'lib/screens/native_hubs_screen.dart',
    'lib/screens/parity_extra_screens.dart',
    'lib/widgets/battle_collection_progress.dart',
    'test/v216_progression_ux_test.dart',
    'test/v216_progression_visual_test.dart',
    'tool/v216_progression_sheets.cjs',
    'lib/theme/luno_theme.dart',
    'assets/fonts/nunito/nunito-variable.ttf',
    'assets/fonts/cinzel-latin.ttf',
    'assets/fonts/cinzel-turkish.ttf',
    'assets/native_art/collection-scene-v28.png',
    'assets/native_art/v205-card-face.png',
    'qa/v216/progression-finish-verified.txt',
  ];
  const sharedScopes = {
    'lib/screens/native_hubs_screen.dart': ['class CollectionScreen ', 'class CollectionBrowserScreen '],
    'lib/screens/parity_extra_screens.dart': ['class ArenasScreen ', 'class LevelRewardsScreen '],
  };
  fs.writeFileSync(path.join(root, 'progression-finish-manifest.json'), JSON.stringify({
    createdUtc: new Date().toISOString(),
    dimensions: ['320x568', '390x844', '430x932', '768x1024'],
    languages: ['tr', 'en'], textScales: [1, 1.5],
    beforeCaptures: records.filter(record => record.phase === 'before').length,
    afterCaptures: records.filter(record => record.phase === 'after').length,
    files: files.map(file => {
      let content = fs.readFileSync(path.resolve(root, '../..', file));
      const scope = sharedScopes[file];
      if (scope) {
        const source = content.toString('utf8');
        const start = source.indexOf(scope[0]);
        const end = source.indexOf(scope[1], start);
        if (start < 0 || end <= start) throw Error(`Missing owned scope in ${file}`);
        content = Buffer.from(source.slice(start, end));
      }
      return {file, scope: scope ? scope.join(' .. before ') : 'whole file',
        sha256: crypto.createHash('sha256').update(content).digest('hex')};
    }),
  }, null, 2));
  console.log(JSON.stringify({captures: records.length, nonblank: records.every(r => r.nonblank)}));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
