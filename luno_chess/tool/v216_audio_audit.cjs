// Read-only production-asset audit. Outputs are confined to qa/v216.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const phase = process.argv[2] || 'before';
if (!['before', 'after'].includes(phase)) throw Error('Expected before or after');
const out = path.join(root, 'qa/v216', phase, 'audio');
const assetDir = path.join(root, 'assets/audio');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const generated = new Map();
for (const script of ['build_battle_audio_v209.cjs', 'build_card_audio_v210.cjs', 'build_semantic_audio_v214.cjs']) {
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, script), 'utf8'), {
    require(name) {
      if (name === 'fs' || name === 'node:fs') return {
        writeFileSync(file, bytes) { generated.set(path.basename(file), {script, hash: hash(bytes)}); },
      };
      if (name === 'path' || name === 'node:path') return path;
      if (name === 'node:crypto') return crypto;
      throw Error(`Unexpected generator dependency ${name}`);
    },
    __dirname, Buffer, process: {stdout: {write() {}}},
  }, {timeout: 5000});
}

function decode(bytes) {
  if (bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.toString('ascii', 8, 12) !== 'WAVE') throw Error('Not WAV');
  let format, data;
  for (let i = 12; i + 8 <= bytes.length;) {
    const size = bytes.readUInt32LE(i + 4), type = bytes.toString('ascii', i, i + 4);
    if (i + 8 + size > bytes.length) throw Error('Truncated RIFF chunk');
    if (type === 'fmt ') format = bytes.subarray(i + 8, i + 8 + size);
    if (type === 'data') data = bytes.subarray(i + 8, i + 8 + size);
    i += 8 + size + (size & 1);
  }
  if (!format || !data || format.readUInt16LE(0) !== 1 || format.readUInt16LE(14) !== 16) throw Error('Expected PCM16');
  const channels = format.readUInt16LE(2), rate = format.readUInt32LE(4);
  if (channels !== 1 || rate !== 22050 || data.length % 2) throw Error('Unexpected PCM dimensions');
  const samples = Array.from({length: data.length / 2}, (_, i) => data.readInt16LE(i * 2) / 32768);
  return {samples, rate, channels};
}

async function main() {
  fs.mkdirSync(out, {recursive: true});
  const rows = [];
  const tiles = [];
  const width = 420, height = 110;
  for (const name of fs.readdirSync(assetDir).filter(n => n.endsWith('.wav')).sort()) {
    const bytes = fs.readFileSync(path.join(assetDir, name));
    const {samples, rate, channels} = decode(bytes);
    let peak = 0, sum = 0, clipped = 0, dc = 0;
    for (const value of samples) { peak = Math.max(peak, Math.abs(value)); sum += value * value; dc += value; if (Math.abs(value) >= .999) clipped++; }
    const rms = Math.sqrt(sum / samples.length), durationMs = samples.length / rate * 1000;
    const provenance = generated.get(name);
    if (provenance && provenance.hash !== hash(bytes)) throw Error(`Generator mismatch: ${name}`);
    const row = {name, sha256: hash(bytes), durationMs, rate, channels, peak, rms, dc: dc / samples.length, clipped,
      first: samples[0], last: samples.at(-1), provenance: provenance ? `tool/${provenance.script} (byte-identical in-memory regeneration)` : 'tool/generate_audio_assets.dart (source audit only)'};
    rows.push(row);
    let waveform = '';
    for (let x = 0; x < 400; x++) {
      const start = Math.floor(x / 400 * samples.length), end = Math.max(start + 1, Math.floor((x + 1) / 400 * samples.length));
      let min = 0, max = 0;
      for (let i = start; i < end; i++) { min = Math.min(min, samples[i]); max = Math.max(max, samples[i]); }
      waveform += `<path d="M${10 + x} ${71 - max * 34}V${71 - min * 34}"/>`;
    }
    const svg = `<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="#171d24"/><text x="10" y="18" fill="#f2f6fa" font-family="Arial" font-size="13">${name}</text><text x="10" y="35" fill="#b5c9d9" font-family="Arial" font-size="11">${durationMs.toFixed(0)} ms | P ${peak.toFixed(3)} | RMS ${rms.toFixed(3)} | clip ${clipped}</text><path d="M10 71H410" stroke="#42515e"/><g stroke="#62d9c7" stroke-width="1">${waveform}</g></svg>`;
    tiles.push(await sharp(Buffer.from(svg)).png().toBuffer());
  }
  if (new Set(rows.map(row => row.sha256)).size !== rows.length) throw Error('Duplicate audio files');
  if (rows.some(row => row.clipped || !Number.isFinite(row.rms) || row.rms === 0)) throw Error('Invalid audio');
  for (let page = 0; page * 18 < tiles.length; page++) {
    const group = tiles.slice(page * 18, (page + 1) * 18);
    await sharp({create: {width: width * 3, height: height * Math.ceil(group.length / 3), channels: 4, background: '#171d24'}})
      .composite(group.map((input, i) => ({input, left: i % 3 * width, top: Math.floor(i / 3) * height})))
      .png().toFile(path.join(out, `waveforms-${page + 1}.png`));
  }
  const names = fs.readdirSync(out).filter(name => /^settings-(tr|en)-\d+-[\d.]+\.png$/.test(name)).sort();
  for (let page = 0; page * 8 < names.length; page++) {
    const group = names.slice(page * 8, (page + 1) * 8), composites = [];
    for (let i = 0; i < group.length; i++) {
      const image = sharp(path.join(out, group[i]));
      const stats = await image.stats();
      if (stats.channels.slice(0, 3).every(channel => channel.stdev < 1)) throw Error(`Blank render ${group[i]}`);
      composites.push({input: await image.resize({width: 300, height: 480, fit: 'contain', background: '#171d24'}).png().toBuffer(), left: i % 4 * 300, top: Math.floor(i / 4) * 505 + 25});
      const label = `<svg width="300" height="25" xmlns="http://www.w3.org/2000/svg"><text x="4" y="17" fill="white" font-family="Arial" font-size="12">${group[i]}</text></svg>`;
      composites.push({input: Buffer.from(label), left: i % 4 * 300, top: Math.floor(i / 4) * 505});
    }
    await sharp({create: {width: 1200, height: 1010, channels: 4, background: '#171d24'}}).composite(composites).png().toFile(path.join(out, `settings-sheet-${page + 1}.png`));
  }
  fs.writeFileSync(path.join(out, 'pcm-audit.json'), JSON.stringify(rows, null, 2));
  console.log(JSON.stringify({assets: rows.length, distinct: new Set(rows.map(row => row.sha256)).size, byteVerifiedGenerators: generated.size, clipped: rows.reduce((sum, row) => sum + row.clipped, 0), settingsRenders: names.length}));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
