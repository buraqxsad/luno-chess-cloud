const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const rate = 22050;
const sine = (hz, t) => Math.sin(2 * Math.PI * hz * t);
const bell = (hz, t, decay = 7) => t < 0 ? 0
  : (sine(hz, t) + .27 * sine(hz * 2.013, t) + .09 * sine(hz * 3.97, t)) * Math.exp(-t * decay);
const sweep = (start, end, duration, t) => {
  const u = Math.min(t, duration);
  return Math.sin(2 * Math.PI * (start * u + (end - start) * u * u / (2 * duration)
    + end * Math.max(0, t - duration)));
};
const pulse = (t, at, hz, decay = 16) => t < at ? 0 : bell(hz, t - at, decay);
let seed = 210;
const noise = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 0x100000000 * 2 - 1; };
// Timbral gestures are deliberately authored per ability, not a pitch-shifted shared file.
const cues = {
  radar: [.72, t => .2 * (pulse(t, .04, 1047) + pulse(t, .23, 1047) + pulse(t, .47, 1568)) + .05 * sweep(280, 1100, .72, t) * Math.exp(-t * 6)],
  prophecy: [.9, t => .13 * (pulse(t, 0, 659, 5) + pulse(t, .16, 988, 5) + pulse(t, .33, 1318, 6)) + .03 * sine(220, t) * Math.exp(-t * 5)],
  shelter: [.75, t => .18 * bell(392, t, 5) + .1 * bell(587, t, 5) + .06 * pulse(t, .1, 1175, 9)],
  chain: [.6, t => .19 * (pulse(t, .01, 735, 30) + pulse(t, .12, 913, 30) + pulse(t, .24, 667, 24)) + .055 * noise() * Math.exp(-t * 11)],
  slow: [.8, t => .15 * (pulse(t, 0, 740, 26) + pulse(t, .24, 554, 26) + pulse(t, .57, 415, 24))],
  pawn_deviation: [.56, t => .16 * sweep(320, 900, .56, t) * Math.exp(-t * 6) + .13 * pulse(t, .2, 660, 12)],
  pawn_advance: [.64, t => .17 * pulse(t, .02, 440, 10) + .17 * pulse(t, .18, 880, 10) + .12 * pulse(t, .34, 1320, 12)],
  locked_square: [.5, t => .19 * bell(220, t, 13) + .11 * pulse(t, .12, 440, 22) + .055 * noise() * Math.exp(-t * 35)],
  freeze: [.83, t => .11 * bell(1480, t, 5) + .11 * pulse(t, .08, 1976, 6) + .08 * pulse(t, .2, 2637, 7) + .04 * noise() * Math.exp(-t * 13)],
  purify: [.84, t => .12 * sweep(620, 1750, .84, t) * Math.exp(-t * 4) + .14 * pulse(t, .27, 1568, 6)],
  mine: [.58, t => .18 * sine(92, t) * Math.exp(-t * 16) + .1 * pulse(t, .12, 330, 25) + .055 * noise() * Math.exp(-t * 24)],
  break_seal: [.62, t => .14 * (pulse(t, .01, 247, 15) + pulse(t, .045, 1047, 24) + pulse(t, .13, 1318, 20)) + .11 * noise() * Math.exp(-t * 19)],
  fog: [.95, t => .05 * noise() * Math.sin(Math.PI * t / .95) + .1 * sine(294, t) * Math.exp(-t * 3) * (.6 + .4 * Math.sin(t * 22))],
  mana_sabotage: [.7, t => .18 * sweep(880, 140, .7, t) * Math.exp(-t * 5) + .06 * bell(176, t, 8)],
  card_block: [.52, t => .16 * bell(196, t, 16) + .14 * pulse(t, .08, 208, 20) + .05 * noise() * Math.exp(-t * 24)],
  rook_bend: [.68, t => .16 * pulse(t, .02, 349, 12) + .16 * pulse(t, .25, 698, 13) + .07 * pulse(t, .4, 1047, 18)],
  angry_n: [.63, t => .16 * sine(120, t) * Math.exp(-t * 18) + .19 * pulse(t, .16, 523, 10) + .1 * pulse(t, .32, 784, 14)],
  shadow_pass: [.86, t => .13 * sweep(700, 180, .43, t) * Math.exp(-t * 5) + .11 * pulse(t, .4, 988, 7)],
  hunt_vow: [.72, t => .15 * pulse(t, .01, 880, 20) + .15 * pulse(t, .18, 1175, 17) + .13 * pulse(t, .42, 1760, 13)],
  watch_vow: [.78, t => .16 * bell(698, t, 5) + .11 * pulse(t, .27, 1047, 8)],
  echo: [.92, t => .19 * pulse(t, 0, 784, 12) + .13 * pulse(t, .22, 784, 12) + .085 * pulse(t, .44, 784, 12) + .05 * pulse(t, .66, 784, 12)],
  fate_exchange: [.94, t => .13 * (pulse(t, 0, 523, 8) + pulse(t, .16, 659, 8) + pulse(t, .32, 784, 8) + pulse(t, .5, 1047, 8))],
  shadow_contract: [.88, t => .12 * bell(262, t, 5) + .1 * bell(330, t, 5) + .13 * pulse(t, .34, 659, 8)],
  board_seal: [.8, t => .19 * bell(147, t, 8) + .11 * bell(440, t, 7) + .09 * pulse(t, .23, 587, 10) + .05 * noise() * Math.exp(-t * 25)],
};
for (const [name, [duration, sample]] of Object.entries(cues)) {
  seed = crypto.createHash('sha256').update(name).digest().readUInt32LE();
  const count = Math.ceil(duration * rate), pcm = Buffer.alloc(count * 2);
  for (let i = 0; i < count; i++) {
    const t = i / rate, fade = Math.max(0, Math.min(1, t / .008, (duration - t) / .04));
    const value = Math.tanh(sample(t) * 1.15) * .78 * fade;
    pcm.writeInt16LE(Math.round(value * 32767), i * 2);
  }
  const header = Buffer.alloc(44);
  header.write('RIFF'); header.writeUInt32LE(36 + pcm.length, 4); header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 2, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34); header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  const bytes = Buffer.concat([header, pcm]);
  fs.writeFileSync(path.join(__dirname, '..', 'assets', 'audio', `spell_${name}.wav`), bytes);
  process.stdout.write(`${name}: ${bytes.length} bytes\n`);
}
