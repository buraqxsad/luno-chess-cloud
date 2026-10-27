const fs = require('fs');
const path = require('path');
const rate = 22050;
let seed = 209;
const noise = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 0x100000000 * 2 - 1; };
const tone = (hz, t) => Math.sin(2 * Math.PI * hz * t);
const bell = (hz, t, decay) => (tone(hz, t) + .28 * tone(hz * 2.01, t) + .1 * tone(hz * 3.97, t)) * Math.exp(-t * decay);
const cues = {
  card_draw: [.34, t => .24 * bell(740 + 900 * t, t, 10) + .1 * noise() * Math.exp(-t * 24)],
  card_cast: [.48, t => .25 * bell(420 + 420 * t, t, 6) + .055 * noise() * Math.exp(-t * 9)],
  card_discard: [.38, t => .19 * bell(520 - 700 * t, t, 9) + .09 * noise() * Math.exp(-t * 12)],
  card_frost: [.66, t => .13 * bell(1320, t, 7) + .1 * bell(1760, t, 5) + .06 * noise() * Math.exp(-t * 12)],
  card_shield: [.65, t => .16 * bell(523.25, t, 5) + .12 * bell(783.99, t, 6)],
  card_arcane: [.62, t => .16 * bell(659.25, t, 6) + .1 * bell(987.77, t, 5)],
  card_strike: [.4, t => .19 * tone(135 - 70 * t, t) * Math.exp(-t * 15) + .13 * noise() * Math.exp(-t * 24) + .055 * bell(880, t, 9)],
  lesson_complete: [.85, t => [523.25, 659.25, 783.99].reduce((sum, hz, i) => sum + (t >= i * .12 ? .15 * bell(hz, t - i * .12, 6) : 0), 0)],
};
const out = path.join(__dirname, '..', 'assets', 'audio');
for (const [name, [duration, sample]] of Object.entries(cues)) {
  const count = Math.ceil(duration * rate), pcm = Buffer.alloc(count * 2);
  for (let i = 0; i < count; i++) {
    const t = i / rate;
    const fade = Math.min(1, t / .008, (duration - t) / .025);
    pcm.writeInt16LE(Math.round(Math.max(-.85, Math.min(.85, sample(t) * fade)) * 32767), i * 2);
  }
  const header = Buffer.alloc(44);
  header.write('RIFF'); header.writeUInt32LE(36 + pcm.length, 4); header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 2, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34); header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  const file = path.join(out, name + '.wav');
  fs.writeFileSync(file, Buffer.concat([header, pcm]));
  process.stdout.write(`${name}: ${count} samples, ${44 + pcm.length} bytes\n`);
}
