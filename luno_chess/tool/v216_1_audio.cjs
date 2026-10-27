// Original, deterministic modal/noise synthesis; no samples or external media.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const qa = path.join(root, 'qa/v216_1');
const assets = path.join(root, 'assets/audio');
const rate = 22050;
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sine = (hz, t) => Math.sin(2 * Math.PI * hz * t);
const envelope = (t, attack, decay) => t < 0 ? 0 : (1 - Math.exp(-t / attack)) * Math.exp(-t / decay);
const modal = (hz, t, decay = .1, brightness = .2) => t < 0 ? 0 :
  envelope(t, .0015, decay) * (sine(hz, t) + brightness * sine(hz * 2.76, t) + .08 * sine(hz * 5.4, t));
const chime = (hz, t, decay = .16) => modal(hz, t, decay, .12);
const glide = (a, b, t, duration) => t < 0 ? 0 :
  sine(1, a * t + (b - a) * Math.min(t, duration) ** 2 / (2 * duration) + (b - a) * Math.max(0, t - duration));
const notes = (t, frequencies, step, decay = .16) => frequencies.reduce((sum, hz, i) =>
  sum + chime(hz, t - i * step, decay) / Math.sqrt(frequencies.length), 0);

// Durations of replaced gameplay files stay identical to V216 timing budgets.
const cues = {
  move: [.16, .047, (t, n) => .7 * modal(310, t, .025, .1) + .22 * modal(850, t, .012) + .18 * n * envelope(t, .0007, .008)],
  capture: [.22, .055, (t, n) => .7 * modal(180, t, .047) + .35 * modal(540, t - .014, .025) + .3 * n * envelope(t, .001, .018)],
  mine_triggered: [.48, .058, (t, n) => .65 * glide(130, 52, t, .16) * envelope(t, .002, .07) + .42 * n * envelope(t, .001, .035) + .12 * modal(960, t - .025, .09)],
  spell_mine: [.58, .039, (t, n) => .65 * modal(112, t, .055) + .25 * modal(380, t - .08, .028) + .12 * n * envelope(t, .001, .016)],
  spell_freeze: [.83, .043, (t, n) => .6 * chime(1320, t, .13) + .32 * chime(1867, t - .035, .16) + .2 * chime(2640, t - .085, .17) + .09 * n * envelope(t, .004, .06)],
  spell_board_seal: [.8, .049, (t, n) => .55 * modal(147, t, .12) + .3 * modal(294, t, .08) + .18 * modal(735, t - .026, .09) + .18 * n * envelope(t, .001, .022)],
  spell_fate_exchange: [.94, .042, t => .4 * glide(420, 840, t, .32) * envelope(t, .006, .13) + .4 * glide(840, 420, t - .04, .32) * envelope(t - .04, .006, .13) + .38 * chime(660, t - .12, .21)],
  victory: [1.35, .055, t => notes(t, [392, 494, 587, 784], .13, .23) + .16 * chime(196, t, .32) + .14 * chime(1175, t - .39, .22)],
  card_unlock: [.9, .045, t => notes(t, [587, 880, 1175], .1, .18) + .13 * chime(294, t, .23)],
  costume_unlock: [.95, .047, t => .5 * chime(262, t, .2) + notes(t - .045, [392, 523, 659], .09, .2)],
  emote_unlock: [.82, .041, t => notes(t, [659, 988, 1318], .085, .14)],
  costume_equip: [.24, .038, t => .6 * modal(340, t, .028) + .24 * chime(680, t - .035, .05)],
  emote_smile: [.42, .030, t => notes(t, [660, 880], .10, .065)],
  emote_heart: [.58, .031, t => .6 * chime(392, t, .11) + .5 * chime(494, t - .13, .13)],
  emote_laugh: [.54, .031, t => notes(t, [784, 988, 784], .105, .055)],
  emote_cry: [.6, .029, t => .6 * glide(740, 440, t, .25) * envelope(t, .008, .1) + .2 * chime(440, t - .26, .08)],
  emote_angry: [.44, .032, (t, n) => .55 * modal(196, t, .045) + .4 * modal(208, t - .1, .04) + .12 * n * envelope(t, .001, .014)],
  emote_think: [.62, .028, t => .65 * chime(523, t, .065) + .4 * chime(587, t - .25, .10)],
  emote_fire: [.64, .032, (t, n) => .45 * glide(180, 430, t, .24) * envelope(t, .006, .1) + .35 * n * envelope(t, .004, .065) + .2 * chime(880, t - .2, .1)],
  emote_star: [.66, .030, t => notes(t, [1047, 1568, 2093], .07, .11)],
  emote_thunder: [.46, .034, (t, n) => .55 * modal(98, t, .06) + .4 * n * envelope(t, .001, .025) + .18 * chime(1480, t - .025, .06)],
  emote_bomb: [.56, .033, (t, n) => .6 * glide(220, 65, t, .15) * envelope(t, .002, .055) + .25 * n * envelope(t, .001, .02) + .3 * modal(330, t - .17, .035)],
  emote_strat: [.67, .030, t => notes(t, [440, 554, 660], .16, .065)],
  emote_trophy: [.8, .033, t => notes(t, [392, 587, 784], .1, .18) + .2 * chime(196, t, .21)],
  emote_crown: [.86, .033, t => .5 * chime(330, t, .18) + .4 * chime(494, t - .09, .2) + .35 * chime(740, t - .19, .23)],
  emote_rainbow: [.98, .032, t => notes(t, [523, 659, 784, 988, 1175], .085, .18)],
};

function render(name) {
  const [seconds, targetRms, voice] = cues[name];
  let seed = crypto.createHash('sha256').update(`luno-v216.1:${name}`).digest().readUInt32LE();
  let low = 0, dc = 0;
  const count = Math.round(seconds * rate);
  const samples = new Float64Array(count);
  for (let i = 0; i < count; i++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    low += .38 * (seed / 0x80000000 - 1 - low);
    const t = i / rate;
    const fade = Math.max(0, Math.min(1, t / .002, (seconds - t) / .045));
    samples[i] = voice(t, low) * fade;
    dc += samples[i];
  }
  dc /= count;
  let sum = 0, peak = 0;
  for (let i = 0; i < count; i++) {
    samples[i] -= dc * Math.sin(Math.PI * i / (count - 1)) ** 2 * 2;
    sum += samples[i] ** 2;
    peak = Math.max(peak, Math.abs(samples[i]));
  }
  const gain = Math.min(targetRms / Math.sqrt(sum / count), .32 / peak);
  const bytes = Buffer.alloc(44 + count * 2);
  bytes.write('RIFF'); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVEfmt ', 8);
  bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(rate, 24); bytes.writeUInt32LE(rate * 2, 28);
  bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34); bytes.write('data', 36);
  bytes.writeUInt32LE(count * 2, 40);
  for (let i = 0; i < count; i++) bytes.writeInt16LE(Math.round(samples[i] * gain * 32767), 44 + i * 2);
  return bytes;
}

function decode(bytes) {
  if (bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.toString('ascii', 8, 12) !== 'WAVE' || bytes.readUInt32LE(4) + 8 !== bytes.length) throw Error('Invalid RIFF');
  let format, pcm;
  for (let at = 12; at + 8 <= bytes.length;) {
    const size = bytes.readUInt32LE(at + 4), type = bytes.toString('ascii', at, at + 4);
    if (at + 8 + size > bytes.length) throw Error('Truncated chunk');
    if (type === 'fmt ') format = bytes.subarray(at + 8, at + 8 + size);
    if (type === 'data') pcm = bytes.subarray(at + 8, at + 8 + size);
    at += 8 + size + (size & 1);
  }
  if (!format || !pcm || format.readUInt16LE(0) !== 1 || format.readUInt16LE(2) !== 1 || format.readUInt16LE(14) !== 16 || format.readUInt32LE(4) !== rate || pcm.length % 2) throw Error('Expected mono 22050 Hz PCM16');
  return Float64Array.from({length: pcm.length / 2}, (_, i) => pcm.readInt16LE(i * 2) / 32768);
}

function spectrum(samples) {
  const n = 1024, power = new Float64Array(n / 2);
  for (let start = 0; start < samples.length; start += 512) {
    const re = new Float64Array(n), im = new Float64Array(n);
    for (let i = 0; i < n; i++) re[i] = (samples[start + i] || 0) * (.5 - .5 * Math.cos(2 * Math.PI * i / (n - 1)));
    for (let i = 1, j = 0; i < n; i++) {
      let bit = n >> 1;
      for (; j & bit; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) [re[i], re[j]] = [re[j], re[i]];
    }
    for (let len = 2; len <= n; len *= 2) {
      for (let at = 0; at < n; at += len) {
        for (let k = 0; k < len / 2; k++) {
          const angle = -2 * Math.PI * k / len, a = at + k, b = a + len / 2;
          const r = re[b] * Math.cos(angle) - im[b] * Math.sin(angle);
          const v = re[b] * Math.sin(angle) + im[b] * Math.cos(angle);
          re[b] = re[a] - r; im[b] = im[a] - v; re[a] += r; im[a] += v;
        }
      }
    }
    for (let i = 1; i < n / 2; i++) power[i] += re[i] ** 2 + im[i] ** 2;
  }
  let total = 0, weighted = 0, high = 0;
  const bands = new Array(12).fill(0);
  for (let i = 1; i < power.length; i++) {
    const hz = i * rate / n;
    total += power[i]; weighted += power[i] * hz;
    if (hz >= 4000) high += power[i];
    bands[Math.min(11, Math.max(0, Math.floor(Math.log2(hz / 43) * 1.5)))] += power[i];
  }
  return {centroidHz: weighted / total, above4kEnergy: high / total, bands: bands.map(v => v / total)};
}

function metrics(name, bytes) {
  const samples = decode(bytes);
  let peak = 0, sum = 0, dc = 0, clipped = 0, maxStep = 0, peakAt = 0;
  for (let i = 0; i < samples.length; i++) {
    const v = samples[i];
    if (Math.abs(v) > peak) { peak = Math.abs(v); peakAt = i; }
    sum += v * v; dc += v;
    if (Math.abs(v) >= .999) clipped++;
    if (i) maxStep = Math.max(maxStep, Math.abs(v - samples[i - 1]));
  }
  const threshold = peak * .01;
  const first = samples.findIndex(v => Math.abs(v) > threshold);
  let last = samples.length - 1;
  while (last > 0 && Math.abs(samples[last]) <= threshold) last--;
  const rms = Math.sqrt(sum / samples.length);
  const windows = [];
  for (let start = 0; start < samples.length; start += 441) {
    let energy = 0, count = Math.min(441, samples.length - start);
    for (let i = start; i < start + count; i++) energy += samples[i] ** 2;
    windows.push(Math.sqrt(energy / count));
  }
  return {name, sha256: hash(bytes), durationMs: samples.length / rate * 1000, rate, channels: 1, bits: 16,
    peak, peakDbfs: 20 * Math.log10(peak), rms, rmsDbfs: 20 * Math.log10(rms), dc: dc / samples.length,
    clipped, maxStep, onsetMs: first / rate * 1000, peakAtMs: peakAt / rate * 1000,
    tailBelowMinus40Ms: (samples.length - 1 - last) / rate * 1000,
    first: samples[0], last: samples.at(-1), loopBoundaryStep: Math.abs(samples[0] - samples.at(-1)),
    ...spectrum(samples), windows20ms: windows};
}

function sourceStamp() {
  return Object.fromEntries(['lib/services/luno_audio_service.dart', 'lib/battle_ui/audio_feedback.dart',
    'lib/widgets/cosmetic_emote_art.dart', 'tool/v216_1_audio.cjs'].map(file => [file, hash(fs.readFileSync(path.join(root, file)))]));
}

function audit(phase) {
  if (!['before', 'after'].includes(phase)) throw Error('Expected before or after');
  const out = path.join(qa, phase, 'audio');
  if (phase === 'before' && fs.existsSync(path.join(out, 'metrics.json'))) throw Error('Refusing to overwrite before evidence');
  fs.mkdirSync(out, {recursive: true});
  const rows = fs.readdirSync(assets).filter(n => n.endsWith('.wav')).sort().map(name => {
    const bytes = fs.readFileSync(path.join(assets, name));
    if (phase === 'before') {
      fs.mkdirSync(path.join(out, 'wavs'), {recursive: true});
      fs.writeFileSync(path.join(out, 'wavs', name), bytes);
    }
    return metrics(name, bytes);
  });
  const report = {phase, generatedUtc: new Date().toISOString(), sourceStamp: sourceStamp(), rows};
  fs.writeFileSync(path.join(out, 'metrics.json'), JSON.stringify(report, null, 2));
  const table = ['# Technical WAV Inventory', '', 'Not a human audition or perceptual loudness measurement.', '',
    '| WAV | ms | Peak dBFS | RMS dBFS | Onset ms | Centroid Hz | >4k energy | Clipped |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    ...rows.map(r => `| ${r.name} | ${r.durationMs.toFixed(0)} | ${r.peakDbfs.toFixed(1)} | ${r.rmsDbfs.toFixed(1)} | ${r.onsetMs.toFixed(1)} | ${r.centroidHz.toFixed(0)} | ${(r.above4kEnergy * 100).toFixed(1)}% | ${r.clipped} |`)];
  fs.writeFileSync(path.join(out, 'inventory.md'), table.join('\n') + '\n');
  if (phase === 'after') {
    const before = JSON.parse(fs.readFileSync(path.join(qa, 'before/audio/metrics.json'))).rows;
    const comparisons = before.map(old => ({name: old.name, changed: old.sha256 !== rows.find(r => r.name === old.name).sha256,
      before: old, after: rows.find(r => r.name === old.name)}));
    fs.writeFileSync(path.join(out, 'comparison.json'), JSON.stringify(comparisons, null, 2));
  }
  if (rows.some(r => r.clipped || !Number.isFinite(r.rms) || r.rms <= 0)) throw Error('Invalid waveform');
  if (new Set(rows.map(r => r.sha256)).size !== rows.length) throw Error('Duplicate waveform');
  console.log(JSON.stringify({phase, files: rows.length, clipped: rows.reduce((n, r) => n + r.clipped, 0), unique: new Set(rows.map(r => r.sha256)).size}));
}

function generate() {
  if (!fs.existsSync(path.join(qa, 'before/audio/metrics.json'))) throw Error('Run audit before first');
  const manifest = [];
  for (const name of Object.keys(cues)) {
    const bytes = render(name);
    fs.writeFileSync(path.join(assets, `${name}.wav`), bytes);
    manifest.push({name: `${name}.wav`, sha256: hash(bytes), durationMs: cues[name][0] * 1000,
      targetRms: cues[name][1], author: 'Original procedural synthesis authored for Luno V216.1',
      sources: ['tool/v216_1_audio.cjs'], externalSamples: false, humanAudition: 'pending'});
  }
  fs.writeFileSync(path.join(qa, 'audio-provenance.json'), JSON.stringify(manifest, null, 2));
  console.log(JSON.stringify({generated: manifest.length, provenance: 'qa/v216_1/audio-provenance.json'}));
}

function verify() {
  for (const name of Object.keys(cues)) {
    if (!render(name).equals(fs.readFileSync(path.join(assets, `${name}.wav`)))) throw Error(`Regeneration mismatch: ${name}`);
  }
  console.log(`Verified ${Object.keys(cues).length} byte-identical original cues`);
}

module.exports = {cues, render, decode, metrics, rate, root, qa, assets, hash};
if (require.main === module) {
  const [command, phase] = process.argv.slice(2);
  if (command === 'audit') audit(phase);
  else if (command === 'generate') generate();
  else if (command === 'verify') verify();
  else throw Error('Usage: node tool/v216_1_audio.cjs audit before|after / generate / verify');
}
