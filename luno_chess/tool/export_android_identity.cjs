const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

async function main() {
  const root = path.resolve(__dirname, '..');
  const res = path.join(root, 'android/app/src/main/res');
  const portrait = path.join(root, 'assets/native_art/luno-portrait-v212.webp');
  const mascot = await sharp(portrait).trim().resize(312, 312, {fit: 'inside'}).png().toBuffer();
  const fg = await sharp({create: {width: 512, height: 512, channels: 4, background: '#00000000'}})
    .composite([{input: mascot, gravity: 'center'}]).png().toBuffer();
  const rgba = await sharp(fg).raw().toBuffer();
  for (let i = 0; i < rgba.length; i += 4) rgba[i] = rgba[i + 1] = rgba[i + 2] = 255;
  await sharp(fg).toFile(path.join(res, 'drawable-nodpi/luno_launcher_art.png'));
  await sharp(rgba, {raw: {width: 512, height: 512, channels: 4}}).png()
    .toFile(path.join(res, 'drawable-nodpi/luno_launcher_mask.png'));
  const icon = await sharp({create: {width: 512, height: 512, channels: 4, background: '#080F18'}})
    .composite([{input: fg}]).png().toBuffer();
  for (const [density, size] of Object.entries({mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192})) {
    await sharp(icon).resize(size, size).png().toFile(path.join(res, `mipmap-${density}/ic_launcher.png`));
  }
  fs.mkdirSync(path.join(root, 'qa/source-audit'), {recursive: true});
  await sharp(icon).toFile(path.join(root, 'qa/source-audit/launcher-preview.png'));
  console.log('Luno launcher: five densities, adaptive foreground and monochrome mask exported.');
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
