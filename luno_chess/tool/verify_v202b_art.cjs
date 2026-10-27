const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const assets = path.join(root, 'assets/native_art');
const goldens = path.join(root, 'test/battle_ui/goldens');
const output = path.join(root, 'qa/v202b-contact');

async function alphaBounds(file) {
  const {data, info} = await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  let left = info.width, top = info.height, right = -1, bottom = -1, opaque = 0;
  for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
    if (data[(y * info.width + x) * 4 + 3] > 8) {
      opaque++; left = Math.min(left, x); top = Math.min(top, y);
      right = Math.max(right, x); bottom = Math.max(bottom, y);
    }
  }
  return {width: info.width, height: info.height, left, top, right, bottom, opaque};
}

(async () => {
  fs.mkdirSync(output, {recursive: true});
  const pieces = fs.readdirSync(assets).filter(f => f.startsWith('battle-v202b-piece-'));
  assert.equal(pieces.length, 12);
  const bounds = {};
  for (const file of pieces) {
    const b = await alphaBounds(path.join(assets, file));
    assert.equal(b.width, 256, file); assert.equal(b.height, 256, file);
    assert(b.opaque > 4000, `Empty/sparse sprite: ${file}`);
    assert(b.left >= 4 && b.right <= 251 && b.top >= 8 && b.bottom <= 247, `Clipped sprite: ${file}`);
    assert(Math.abs((b.left + b.right) / 2 - 127.5) <= 2, `Off-center sprite: ${file}`);
    bounds[file] = b;
  }
  const bases = Object.values(bounds).map(b => b.bottom);
  assert(Math.max(...bases) - Math.min(...bases) <= 1, 'Piece base lines drift');
  const {data, info} = await sharp(path.join(assets, 'battle-v202b-board-frame.webp')).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  let centerAlpha = 0;
  for (let y = Math.floor(info.height * .2); y < info.height * .8; y++) {
    for (let x = Math.floor(info.width * .2); x < info.width * .8; x++) {
      centerAlpha = Math.max(centerAlpha, data[(y * info.width + x) * 4 + 3]);
    }
  }
  assert(centerAlpha <= 8, 'Frame contains opaque board-center pixels');
  const auraCenters = {};
  for (const name of ['board-shelter', 'board-freeze']) {
    const aura = await sharp(path.join(assets, `battle-v202b-${name}.webp`)).ensureAlpha().raw().toBuffer({resolveWithObject: true});
    let alpha = 0;
    for (let y = Math.floor(aura.info.height * .35); y < aura.info.height * .65; y++) {
      for (let x = Math.floor(aura.info.width * .35); x < aura.info.width * .65; x++) {
        alpha = Math.max(alpha, aura.data[(y * aura.info.width + x) * 4 + 3]);
      }
    }
    assert(alpha <= 8, `${name} hides the center of the chess piece`);
    auraCenters[name] = alpha;
  }
  const shots = fs.readdirSync(goldens).filter(f => f.endsWith('.png')).sort();
  assert.equal(shots.length, 50, 'Missing screenshot state');
  const screenshots = {};
  for (const file of shots) {
    const image = sharp(path.join(goldens, file));
    const metadata = await image.metadata(), stats = await image.stats();
    assert(stats.channels.slice(0, 3).some(c => c.stdev > 20), `Blank screenshot: ${file}`);
    screenshots[file] = {width: metadata.width, height: metadata.height};
  }
  for (let page = 0; page * 10 < shots.length; page++) {
    const composites = [];
    for (let i = 0; i < 10 && page * 10 + i < shots.length; i++) {
      const file = shots[page * 10 + i], x = i % 5 * 250, y = Math.floor(i / 5) * 585;
      const label = Buffer.from(`<svg width="250" height="30"><rect width="250" height="30" fill="#162331"/><text x="8" y="20" font-family="Arial" font-size="14" fill="white">${file}</text></svg>`);
      const thumb = await sharp(path.join(goldens, file)).resize(240, 550, {fit: 'contain', background: '#080f18'}).png().toBuffer();
      composites.push({input: label, left: x, top: y}, {input: thumb, left: x + 5, top: y + 30});
    }
    await sharp({create: {width: 1250, height: 1170, channels: 4, background: '#080f18'}})
      .composite(composites).png().toFile(path.join(output, `page-${page + 1}.png`));
  }
  const files = fs.readdirSync(assets).filter(f => f.startsWith('battle-v202b-'));
  const report = {pass: true, generatedAt: new Date().toISOString(), assets: files.length,
    bytes: files.reduce((n, f) => n + fs.statSync(path.join(assets, f)).size, 0),
    centerAlpha, auraCenters, pieceBounds: bounds, screenshots,
    limits: 'Alpha/nonblank checks and contact sheets are not a device performance or whole-game bug-free guarantee.'};
  fs.writeFileSync(path.join(root, 'qa/v202b-art-verification.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({pass: true, assets: report.assets, bytes: report.bytes, pieces: pieces.length, screenshots: shots.length, centerAlpha}));
})().catch(error => {console.error(error); process.exitCode = 1;});
