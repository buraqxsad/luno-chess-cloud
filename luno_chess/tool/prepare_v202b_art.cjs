const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'design/v202b/source');
const destination = path.join(root, 'assets/native_art');
async function asset(input, name, rectangle, width, height) {
  let image = sharp(path.join(source, input));
  if (rectangle) image = sharp(await image.extract(rectangle).toBuffer());
  if (name !== 'background') image = image.trim({ threshold: 8 });
  await image.resize(width, height, { fit: 'inside', withoutEnlargement: true })
    .webp({ quality: 86, alphaQuality: 100 }).toFile(path.join(destination, `battle-v202b-${name}.webp`));
}
(async () => {
  const glyphs = ['mana', 'info', 'arsenal', 'phase-card', 'phase-move', 'knowledge', 'menu', 'close', 'confirm', 'pass', 'discard', 'sync'];
  for (let i = 0; i < glyphs.length; i++) await asset('glyphs.png', glyphs[i],
    { left: (i % 4) * 362, top: Math.floor(i / 4) * 362, width: 362, height: 362 }, 128, 128);
  const effects = ['mine', 'locked-square', 'board-seal', 'fog', 'shelter', 'freeze', 'chain', 'slow', 'vow'];
  for (let i = 0; i < effects.length; i++) await asset('effects.png', effects[i],
    { left: (i % 3) * 426, top: Math.floor(i / 3) * 410, width: 426, height: 410 }, 256, 256);
  await asset('card-frame.png', 'card-frame', { left: 104, top: 40, width: 841, height: 1380 }, 360, 600);
  await asset('board-frame-clean.png', 'board-frame', null, 640, 640);
  await asset('skins-refined.png', 'clock-panel', { left: 850, top: 290, width: 650, height: 210 }, 480, 160);
  await asset('skins-refined.png', 'command-panel', { left: 42, top: 818, width: 920, height: 152 }, 640, 128);
  await asset('skins-refined.png', 'phase-panel', { left: 1008, top: 818, width: 495, height: 152 }, 360, 130);
  await asset('background.png', 'background', null, 720, 1280);
  const auraSheet = await sharp(path.join(source, 'board-auras.png')).metadata();
  const auraCell = Math.floor(auraSheet.width / 2);
  for (const [column, name] of ['board-shelter', 'board-freeze'].entries()) {
    await asset('board-auras.png', name, {left: column * auraCell, top: 0, width: auraCell, height: auraSheet.height}, 256, 256);
  }
  const names = ['king', 'queen', 'rook', 'bishop', 'knight', 'pawn'];
  const columns = [[12, 256], [272, 272], [548, 234], [794, 232], [1016, 276], [1298, 230]];
  const heights = [224, 222, 200, 212, 206, 176];
  for (let row = 0; row < 2; row++) {
    for (let column = 0; column < 6; column++) {
      const crop = sharp(path.join(source, 'pieces.png')).extract({
        left: columns[column][0], top: row ? 540 : 80, width: columns[column][1], height: 450,
      });
      const { data, info } = await crop.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      let left = info.width, top = info.height, right = 0, bottom = 0;
      // Bound the actual alpha silhouette, not unused RGB under transparent pixels.
      for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
        if (data[(y * info.width + x) * 4 + 3] > 8) {
          left = Math.min(left, x); top = Math.min(top, y);
          right = Math.max(right, x); bottom = Math.max(bottom, y);
        }
      }
      if (left >= right || top >= bottom) throw new Error(`Empty piece ${row}:${column}`);
      const sprite = await sharp(data, { raw: info }).extract({ left, top, width: right-left+1, height: bottom-top+1 })
        .resize({ height: heights[column] }).png().toBuffer();
      const bounds = await sharp(sprite).metadata();
      await sharp({ create: { width: 256, height: 256, channels: 4, background: '#00000000' } })
        .composite([{ input: sprite, left: Math.floor((256-bounds.width)/2), top: 239-bounds.height }])
        .webp({ quality: 90, alphaQuality: 100 })
        .toFile(path.join(destination, `battle-v202b-piece-${row ? 'b' : 'w'}-${names[column]}.webp`));
    }
  }
  const files = fs.readdirSync(destination).filter(f => f.startsWith('battle-v202b-'));
  console.log(JSON.stringify({ files: files.length, bytes: files.reduce((n, f) => n + fs.statSync(path.join(destination, f)).size, 0) }));
})().catch(error => { console.error(error); process.exitCode = 1; });
