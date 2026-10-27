const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const art = path.join(root, 'assets/native_art');
const qa = path.join(root, 'qa/v216/costume-art');
const types = ['king', 'queen', 'rook', 'bishop', 'knight', 'pawn'];
const sets = ['ottoman', 'roma', 'brit', 'viking', 'tasdevri', 'samuray', 'ice', 'dragon', 'neon'];

async function reference() {
  fs.mkdirSync(qa, {recursive: true});
  const tiles = [];
  for (let row = 0; row < 2; row++) {
    for (let col = 0; col < 6; col++) {
      const side = row === 0 ? 'w' : 'b';
      const input = await sharp(path.join(art, `battle-v202b-piece-${side}-${types[col]}.webp`))
        .resize(180, 200, {fit: 'contain', background: '#00000000'}).png().toBuffer();
      tiles.push({input, left: col * 200 + 10, top: row * 220 + 10});
    }
  }
  await sharp({create: {width: 1200, height: 440, channels: 4, background: '#00000000'}})
    .composite(tiles).png().toFile(path.join(qa, 'current-base-reference.png'));
  for (const set of sets) {
    const old = [];
    for (let row = 0; row < 2; row++) {
      for (let col = 0; col < 6; col++) {
        const side = row === 0 ? 'w' : 'b';
        const input = await sharp(path.join(art, `piece-${set}-${side}-${types[col]}-v11-mobile.webp`))
          .resize(180, 200, {fit: 'contain', background: '#00000000'}).png().toBuffer();
        old.push({input, left: col * 200 + 10, top: row * 220 + 10});
      }
    }
    await sharp({create: {width: 1200, height: 440, channels: 4, background: '#00000000'}})
      .composite(old).png().toFile(path.join(qa, `before-${set}.png`));
  }
  console.log(JSON.stringify({reference: path.join(qa, 'current-base-reference.png'), sets: sets.length}));
}

async function extract(set, source) {
  if (!sets.includes(set)) throw Error('Unsupported set');
  const metadata = await sharp(source).metadata();
  if (!metadata.hasAlpha) throw Error('Generated sheet must have transparency');
  const out = path.join(qa, 'candidates', set);
  fs.mkdirSync(out, {recursive: true});
  fs.copyFileSync(source, path.join(out, 'generated-sheet.png'));
  const records = [];
  const cells = [];
  const pixels = await sharp(source).ensureAlpha().raw().toBuffer();
  const columns = [0];
  for (let index = 1; index < 6; index++) {
    const desired = Math.floor(index * metadata.width / 6);
    const gaps = [];
    for (let x = desired - Math.floor(metadata.width / 30); x <= desired + metadata.width / 30; x++) {
      let body = 0;
      for (let y = 0; y < metadata.height; y++) body += pixels[(y * metadata.width + x) * 4 + 3] > 20;
      if (body === 0) gaps.push(x);
    }
    if (!gaps.length) throw Error(`Columns overlap at ${index}`);
    gaps.sort((a, b) => Math.abs(a - desired) - Math.abs(b - desired));
    columns.push(gaps[0]);
  }
  columns.push(metadata.width);
  const splits = [];
  for (let col = 0; col < 6; col++) {
    const left = columns[col];
    const right = columns[col + 1];
    const gaps = [];
    for (let y = Math.floor(metadata.height * .42); y < metadata.height * .58; y++) {
      let body = 0;
      for (let x = left; x < right; x++) body += pixels[(y * metadata.width + x) * 4 + 3] > 20;
      if (body === 0) gaps.push(y);
    }
    if (!gaps.length) throw Error(`Rows overlap in column ${col}`);
    gaps.sort((a, b) => Math.abs(a - metadata.height / 2) - Math.abs(b - metadata.height / 2));
    splits.push(gaps[0]);
  }
  for (let row = 0; row < 2; row++) {
    for (let col = 0; col < 6; col++) {
      const left = columns[col];
      const top = row === 0 ? 0 : splits[col];
      const width = columns[col + 1] - left;
      const height = (row === 0 ? splits[col] : metadata.height) - top;
      const cell = await sharp(source).extract({left, top, width, height}).ensureAlpha().raw().toBuffer({resolveWithObject: true});
      let x0 = width, y0 = height, x1 = -1, y1 = -1;
      let borderBody = 0;
      for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        if (cell.data[(y * width + x) * 4 + 3] > 20) {
          x0 = Math.min(x0, x); y0 = Math.min(y0, y);
          x1 = Math.max(x1, x); y1 = Math.max(y1, y);
        }
        if ((x === 0 || y === 0 || x === width - 1 || y === height - 1) &&
            cell.data[(y * width + x) * 4 + 3] > 220) borderBody++;
      }
      if (x1 < x0 || borderBody > 0) {
        throw Error(`Empty/clipped sprite ${set}/${row}/${col}: ${[x0, y0, x1, y1]}`);
      }
      const side = row === 0 ? 'w' : 'b';
      const file = `piece-${set}-${side}-${types[col]}-v216.webp`;
      records.push({file, bounds: [x0, y0, x1, y1], cell: [width, height]});
      cells.push({file, row, left: left + x0, top: top + y0, width: x1 - x0 + 1, height: y1 - y0 + 1});
    }
  }
  for (const cell of cells) {
    const row = cells.filter(item => item.row === cell.row);
    const scale = Math.min(288 / Math.max(...row.map(item => item.height)), 224 / Math.max(...row.map(item => item.width)));
    const width = Math.round(cell.width * scale);
    const height = Math.round(cell.height * scale);
    const sprite = await sharp(source).extract({left: cell.left, top: cell.top, width: cell.width, height: cell.height})
      .resize(width, height).png().toBuffer();
    await sharp({create: {width: 256, height: 320, channels: 4, background: '#00000000'}})
      .composite([{input: sprite, left: Math.floor((256 - width) / 2), top: 304 - height}])
      .webp({lossless: true}).toFile(path.join(out, cell.file));
  }
  fs.writeFileSync(path.join(out, 'extraction.json'), JSON.stringify(records, null, 2));
  console.log(JSON.stringify({set, sprites: records.length, out}));
}

async function compare() {
  const sheets = path.join(qa, 'comparison-sheets');
  fs.mkdirSync(sheets, {recursive: true});
  for (const set of sets) {
    const tiles = [];
    let top = 8;
    for (const size of [28, 40, 52]) {
      const old = path.join(qa, 'boards', `${set}-old-${size}.png`);
      const candidate = path.join(qa, 'boards', `${set}-candidate-${size}.png`);
      const meta = await sharp(old).metadata();
      tiles.push({input: old, left: 8 + Math.floor((492 - meta.width) / 2), top});
      tiles.push({input: candidate, left: 516 + Math.floor((492 - meta.width) / 2), top});
      top += meta.height + 12;
    }
    await sharp({create: {width: 1016, height: top, channels: 4, background: '#253443'}})
      .composite(tiles).png().toFile(path.join(sheets, `${set}.png`));
  }
  console.log(JSON.stringify({sheets, sets: sets.length, rescaled: false}));
}

async function audit() {
  const records = [];
  const hashes = new Set();
  for (const set of sets) for (const side of ['w', 'b']) for (const type of types) {
    const file = `piece-${set}-${side}-${type}-v216.webp`;
    const input = path.join(qa, 'candidates', set, file);
    const bytes = fs.readFileSync(input);
    const hash = crypto.createHash('sha256').update(bytes).digest('hex');
    if (hashes.has(hash)) throw Error(`Duplicate sprite: ${file}`);
    hashes.add(hash);
    const {data, info} = await sharp(input).ensureAlpha().raw().toBuffer({resolveWithObject: true});
    if (info.width !== 256 || info.height !== 320) throw Error(`Unexpected canvas: ${file}`);
    let x0 = 256, y0 = 320, x1 = -1, y1 = -1;
    let opaque = 0, luminance = 0;
    for (let y = 0; y < 320; y++) for (let x = 0; x < 256; x++) {
      const i = (y * 256 + x) * 4;
      if (data[i + 3] > 220) {
        x0 = Math.min(x0, x); y0 = Math.min(y0, y);
        x1 = Math.max(x1, x); y1 = Math.max(y1, y);
        opaque++;
        luminance += .2126 * data[i] + .7152 * data[i + 1] + .0722 * data[i + 2];
      }
    }
    if (opaque < 4000 || x0 < 8 || x1 > 247 || y0 < 8 || y1 > 311) {
      throw Error(`Empty/clipped/overfilled sprite: ${file}`);
    }
    const coverage = {};
    for (const size of [28, 40, 52]) {
      const small = await sharp(input).resize(size, size, {fit: 'contain', background: '#00000000'})
        .ensureAlpha().raw().toBuffer();
      coverage[size] = Array.from({length: size * size}, (_, index) => small[index * 4 + 3])
        .filter(alpha => alpha > 128).length;
      if (coverage[size] < size * size * .1) throw Error(`Unreadably small sprite: ${file}/${size}`);
    }
    records.push({set, side, type, file, bytes: bytes.length, sha256: hash,
      opaqueBounds: [x0, y0, x1, y1], averageBodyLuminance: luminance / opaque, coverage});
  }
  fs.writeFileSync(path.join(qa, 'sprite-audit.json'), JSON.stringify({
    sprites: records.length, uniqueHashes: hashes.size,
    bytes: records.reduce((sum, record) => sum + record.bytes, 0), records,
  }, null, 2));
  console.log(JSON.stringify({sprites: records.length, uniqueHashes: hashes.size,
    bytes: records.reduce((sum, record) => sum + record.bytes, 0)}));
}

async function publish() {
  const records = [];
  for (const set of sets) for (const side of ['w', 'b']) for (const type of types) {
    const file = `piece-${set}-${side}-${type}-v216.webp`;
    const source = path.join(qa, 'candidates', set, file);
    const original = fs.readFileSync(source);
    const compressed = await sharp(original).webp({quality: 92, alphaQuality: 100, effort: 6}).toBuffer();
    const checks = [];
    for (const size of [28, 40, 52]) {
      const options = {fit: 'contain', background: '#00000000'};
      const before = await sharp(original).resize(size, size, options).ensureAlpha().raw().toBuffer();
      const after = await sharp(compressed).resize(size, size, options).ensureAlpha().raw().toBuffer();
      let difference = 0, count = 0, alphaDelta = 0;
      for (let i = 0; i < before.length; i += 4) {
        alphaDelta = Math.max(alphaDelta, Math.abs(before[i + 3] - after[i + 3]));
        if (before[i + 3] > 128) {
          for (let c = 0; c < 3; c++) difference += Math.abs(before[i + c] - after[i + c]);
          count += 3;
        }
      }
      checks.push({size, meanBodyRgbDifference: difference / count, maxAlphaDifference: alphaDelta});
    }
    const acceptable = checks.every(check => check.meanBodyRgbDifference <= 3 && check.maxAlphaDifference === 0);
    const output = acceptable && compressed.length < original.length ? compressed : original;
    fs.writeFileSync(path.join(art, file), output);
    records.push({file, sourceBytes: original.length, bytes: output.length,
      compression: output === compressed ? 'webp-q92-alpha100' : 'lossless-fallback', checks,
      sha256: crypto.createHash('sha256').update(output).digest('hex')});
  }
  fs.writeFileSync(path.join(qa, 'published-assets.json'), JSON.stringify({
    sprites: records.length, sourceBytes: records.reduce((n, item) => n + item.sourceBytes, 0),
    bytes: records.reduce((n, item) => n + item.bytes, 0), records,
  }, null, 2));
  console.log(JSON.stringify({sprites: records.length, bytes: records.reduce((n, item) => n + item.bytes, 0),
    losslessFallbacks: records.filter(item => item.compression === 'lossless-fallback').length}));
}

async function catalog() {
  const records = [];
  for (const set of ['luno', ...sets]) {
    const tiles = [];
    for (let row = 0; row < 2; row++) for (let col = 0; col < 6; col++) {
      const side = row === 0 ? 'w' : 'b';
      const file = set === 'luno'
        ? `battle-v202b-piece-${side}-${types[col]}.webp`
        : `piece-${set}-${side}-${types[col]}-v216.webp`;
      const input = await sharp(path.join(art, file)).resize(144, 180).png().toBuffer();
      tiles.push({input, left: col * 160 + 8, top: row * 200 + 10});
    }
    const file = `piece-set-${set}-v216.webp`;
    const output = await sharp({create: {width: 960, height: 400, channels: 4, background: '#00000000'}})
      .composite(tiles).webp({quality: 94, alphaQuality: 100, effort: 4}).toBuffer();
    fs.writeFileSync(path.join(art, file), output);
    records.push({set, file, roles: types, sides: ['w', 'b'], bytes: output.length,
      sha256: crypto.createHash('sha256').update(output).digest('hex')});
  }
  fs.writeFileSync(path.join(qa, 'catalog-assets.json'), JSON.stringify(records, null, 2));
  console.log(JSON.stringify({atlases: records.length, bytes: records.reduce((n, record) => n + record.bytes, 0)}));
}

const [command, set, source] = process.argv.slice(2);
(command === 'reference' ? reference() : command === 'extract' ? extract(set, source)
  : command === 'compare' ? compare() : command === 'audit' ? audit()
  : command === 'publish' ? publish()
  : command === 'catalog' ? catalog()
  : Promise.reject(Error('Use reference, extract SET SOURCE, compare, audit, publish, or catalog')))
  .catch(error => {console.error(error); process.exitCode = 1;});
