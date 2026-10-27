const fs = require('node:fs');
const path = require('node:path');
const rate = 22050;
const tone = (hz, t, decay) => Math.sin(2 * Math.PI * hz * t) * Math.exp(-t * decay);
const note = (hz, t, at, decay = 12) => t < at ? 0 : tone(hz, t - at, decay);
// Neutral resolution, warning, and mine activation have different envelopes.
const cues = {
  result_draw: [.62, t => .18 * note(392, t, 0, 7) + .16 * note(523.25, t, .12, 7)],
  check: [.34, t => .22 * note(880, t, 0, 20) + .18 * note(1108.73, t, .1, 20)],
  mine_triggered: [.48, t => .25 * tone(78, t, 16) + .12 * tone(147, t, 14)
    + .13 * note(659.25, t, .07, 21) + .09 * note(987.77, t, .15, 24)],
};
for (const [name, [duration, sample]] of Object.entries(cues)) {
  const pcm = Buffer.alloc(Math.ceil(duration * rate) * 2);
  for (let i = 0; i < pcm.length / 2; i++) {
    const t = i / rate;
    const fade = Math.max(0, Math.min(1, t / .008, (duration - t) / .04));
    pcm.writeInt16LE(Math.round(Math.tanh(sample(t)) * .78 * fade * 32767), i * 2);
  }
  const header = Buffer.alloc(44);
  header.write('RIFF'); header.writeUInt32LE(36 + pcm.length, 4);
  header.write('WAVEfmt ', 8); header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 2, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
  header.write('data', 36); header.writeUInt32LE(pcm.length, 40);
  fs.writeFileSync(path.join(__dirname, '..', 'assets', 'audio', `${name}.wav`),
    Buffer.concat([header, pcm]));
  process.stdout.write(`${name}: ${pcm.length + 44} bytes\n`);
}
