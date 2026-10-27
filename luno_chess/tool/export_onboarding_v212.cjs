const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const base = 'C:/Users/Casper/.codex/generated_images/019f5d34-6fc3-71e1-b469-b9e0da8eb51c';
async function main() {
  fs.mkdirSync('art-source/v212', { recursive: true });
  const portrait = path.join(base, 'exec-91550925-030d-44a5-bd6d-ac74efbd7d2f.png');
  const loading = path.join(base, 'exec-9a217ae7-b9b8-4bd0-8070-5632fb8bc88e.png');
  fs.copyFileSync(portrait, 'art-source/v212/luno-portrait.png');
  fs.copyFileSync(loading, 'art-source/v212/loading-scene.png');
  await sharp(portrait).resize(384, 384, { fit: 'contain', background: '#00000000' }).webp({ quality: 90 }).toFile('assets/native_art/luno-portrait-v212.webp');
  await sharp(loading).resize(768, 1152).webp({ quality: 86 }).toFile('assets/native_art/loading-scene-v212.webp');
  const icon = await sharp(portrait).resize(288, 288, { fit: 'contain', background: '#00000000' }).png().toBuffer();
  await sharp({ create: { width: 512, height: 512, channels: 4, background: '#00000000' } }).composite([{ input: icon, gravity: 'centre' }]).png().toFile('android/app/src/main/res/drawable-nodpi/luno_splash_v212.png');
  const button = path.join(base, 'exec-33c5a406-fee3-4acf-aa01-8990ea704f2a.png');
  fs.copyFileSync(button, 'art-source/v212/action-face.png');
  const face = await sharp(button).trim().png().toBuffer();
  await sharp(face).resize({ width: 720 }).webp({ quality: 90 }).toFile('assets/native_art/battle-action-face-v212.webp');
  console.log('V212 loading, starter portrait and Android safe-area splash exported.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
