const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require(process.env.V215_SHARP || 'C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const output = path.resolve(root, process.env.V215_ASSET_OUTPUT_DIR || 'qa/v215/assets');
const relativeOutput = path.relative(path.join(root, 'qa'), output);
if (relativeOutput === '..' || relativeOutput.startsWith('..' + path.sep) || path.isAbsolute(relativeOutput)) {
  throw new Error('Asset audit output must remain inside project qa.');
}
const sets = ['battle_v1', 'luno', 'ottoman', 'roma', 'brit', 'viking', 'tasdevri', 'samuray', 'ice', 'dragon', 'neon'];
const types = ['king', 'queen', 'rook', 'bishop', 'knight', 'pawn'];
function files(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const filename = path.join(directory, entry.name);
    return entry.isDirectory() ? files(filename) : [filename];
  });
}
function label(text, width, height) {
  return Buffer.from(`<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg"><text x="8" y="${height / 2 + 5}" fill="#eeeeee" font-family="Arial" font-size="14">${text}</text></svg>`);
}
async function main() {
  fs.mkdirSync(output, {recursive: true});
  const entries = [];
  for (const filename of files(path.join(root, 'assets'))) {
    const bytes = fs.readFileSync(filename);
    let dimensions = null;
    if (/\.(png|webp|jpg|jpeg)$/i.test(filename)) {
      const info = await sharp(bytes).metadata();
      dimensions = {width: info.width, height: info.height, alpha: info.hasAlpha, format: info.format};
    }
    entries.push({path: path.relative(root, filename).replaceAll('\\', '/'), bytes: bytes.length,
      sha256: crypto.createHash('sha256').update(bytes).digest('hex'), dimensions});
  }
  const groups = new Map();
  for (const entry of entries) groups.set(entry.sha256, [...(groups.get(entry.sha256) || []), entry]);
  const duplicates = [...groups.values()].filter(group => group.length > 1);
  const costume = entries.filter(entry => /piece-(luno|ottoman|roma|brit|viking|tasdevri|samuray|ice|dragon|neon)-[wb]-.*-v(11|22)-mobile\.webp$/.test(entry.path));
  const declaredDirectories = ['assets/native_art/', 'assets/native_art/embedded/', 'assets/native_art/phase2/', 'assets/audio/'];
  const declaredFonts = ['assets/fonts/nunito/nunito-variable.ttf', 'assets/fonts/cinzel-latin.ttf', 'assets/fonts/cinzel-turkish.ttf',
    ...['regular', 'medium', 'semibold'].flatMap(weight => ['latin', 'turkish'].map(language => `assets/fonts/spectral/spectral-${weight}-${language}.ttf`))];
  const declared = entries.filter(entry => declaredDirectories.includes(entry.path.slice(0, entry.path.lastIndexOf('/') + 1)) || declaredFonts.includes(entry.path));
  const manifest = {createdAt: new Date().toISOString(), totalFiles: entries.length,
    totalBytes: entries.reduce((sum, entry) => sum + entry.bytes, 0),
    declaredAssetFiles: declared.length, declaredAssetBytes: declared.reduce((sum, entry) => sum + entry.bytes, 0),
    undeclared: entries.filter(entry => !declared.includes(entry)),
    costumeFiles: costume.length, costumeBytes: costume.reduce((sum, entry) => sum + entry.bytes, 0),
    exactDuplicateGroups: duplicates, duplicateBytes: duplicates.reduce((sum, group) => sum + group.slice(1).reduce((n, entry) => n + entry.bytes, 0), 0),
    largest: [...entries].sort((a, b) => b.bytes - a.bytes).slice(0, 30), entries,
    warning: 'Duplicate and static reachability candidates only. No production deletion or build acceptance.'};
  fs.writeFileSync(path.join(output, 'inventory.json'), JSON.stringify(manifest, null, 2));
  for (const cell of [28, 40, 52]) {
    const rowHeight = cell * 2 + 30, width = 150 + cell * 12;
    const composite = [];
    for (let row = 0; row < sets.length; row++) {
      const set = sets[row];
      composite.push({input: label(set.toUpperCase(), 150, rowHeight), left: 0, top: row * rowHeight});
      for (let side = 0; side < 2; side++) {
        for (let type = 0; type < 6; type++) {
          const filename = set === 'battle_v1'
            ? `battle-v202b-piece-${side === 0 ? 'w' : 'b'}-${types[type]}.webp`
            : `piece-${set}-${side === 0 ? 'w' : 'b'}-${types[type]}-v${set === 'luno' ? '22' : '11'}-mobile.webp`;
          for (let square = 0; square < 2; square++) {
            const squareColor = square === 0 ? '#d8d8cd' : '#263c50';
            const piece = await sharp(path.join(root, 'assets/native_art', filename)).resize(cell, cell, {fit: 'contain', background: '#00000000'}).png().toBuffer();
            const tile = await sharp({create: {width: cell, height: cell, channels: 4, background: squareColor}}).composite([{input: piece}]).png().toBuffer();
            composite.push({input: tile, left: 150 + (side * 6 + type) * cell, top: row * rowHeight + square * cell + 15});
          }
        }
      }
    }
    await sharp({create: {width, height: sets.length * rowHeight, channels: 4, background: '#10151c'}}).composite(composite).png().toFile(path.join(output, `costumes-${cell}px.png`));
  }
  console.log(JSON.stringify({files: manifest.totalFiles, bytes: manifest.totalBytes, costumeFiles: manifest.costumeFiles, costumeBytes: manifest.costumeBytes, duplicateGroups: duplicates.length, duplicateBytes: manifest.duplicateBytes}));
}
main().catch(error => {console.error(error); process.exitCode = 1;});
