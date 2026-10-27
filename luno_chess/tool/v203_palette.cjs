const fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '..');
const files = ['native_hubs_screen', 'deck_screen', 'profile_screen',
  'parity_extra_screens', 'legacy_parity_screens', 'difficulty_screen',
  'play_mode_screen', 'collection_screens', 'friendly_online_screen',
  'online_hub_screen', 'shop_screen'];
// Exact decorative color literals only. No state conditions or values change.
const groups = {
  bgPanel: ['DB173A39','E51B3037','EE3A245E','E1202949','DD20273E','EB343632',
    'ED353C3B','ED192A2E','ED233B3D','FF29423F','ED29423F','FF152D36',
    'E01C292D','CC172B36','DE162E29','ED293D39','FF192D29','ED263B3D',
    'D9173535','FF173531','EB252E30','ED2F4140','FF263B3D','FF315457'],
  bgPanel2: ['E12A354B','CC3A1A32','E02B383B','55201845','FF293E46',
    'ED263B3D','E6233C40','EB413337','EB2C3B3D','ED344044','F52A4545',
    'FF263F40','F211252B'],
  bgRaised: ['CC1B3D3A','ED263E58','E5263D38','E02B4447','FF314F4D',
    'EE365B4F','EE29464A','FF203B39','FF35655D','FF29544D','FF1B3439',
    'D91B3439','ED35564B','EB204754'],
};
const colors = new Map(Object.entries(groups).flatMap(([name, values]) => values.map(v => [v, `LunoColors.${name}`])));
const report = [];
for (const file of files) {
  const target = path.join(root, 'lib/screens', `${file}.dart`);
  const before = fs.readFileSync(target, 'utf8');
  let count = 0;
  const after = before.replace(/(?:const )?Color\(0x([A-F0-9]{8})\)/g, (literal, hex) => {
    if (!colors.has(hex)) return literal;
    count++; return colors.get(hex);
  });
  if (count) { fs.writeFileSync(target, after); report.push({file: `lib/screens/${file}.dart`, replacements: count}); }
}
fs.writeFileSync(path.join(root, 'qa/v203-palette.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report));
