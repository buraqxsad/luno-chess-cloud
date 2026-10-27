const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const crypto = require('crypto');
const fs = require('fs');
const source = 'C:/Users/Casper/.codex/generated_images/019f5d34-6fc3-71e1-b469-b9e0da8eb51c/exec-4c623aeb-670f-44f6-8159-8724587c92cc.png';
const output = 'assets/native_art/battle-impact-v209.webp';
async function main() {
  const meta = await sharp(source).metadata();
  if (!meta.hasAlpha) throw new Error('Generated impact has no alpha');
  await sharp(source).resize(320, 320, { fit: 'contain' }).webp({ quality: 88, alphaQuality: 100 }).toFile(output);
  const { data, info } = await sharp(output).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const centerAlpha = data[(Math.floor(info.height / 2) * info.width + Math.floor(info.width / 2)) * 4 + 3];
  if (centerAlpha !== 0) throw new Error('Impact obscures target center');
  const file = fs.readFileSync(output);
  console.log(JSON.stringify({ output, bytes: file.length, centerAlpha,
    sha256: crypto.createHash('sha256').update(file).digest('hex') }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
