const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const source = process.argv[2];
if (!source) throw Error('Supply the accepted ImageGen output path');

async function main() {
  const evidence = path.join(root, 'qa/v216/friendly-art');
  fs.mkdirSync(evidence, {recursive: true});
  fs.copyFileSync(source, path.join(evidence, 'generated-source.png'));
  const metadata = await sharp(source).metadata();
  if (!metadata.hasAlpha) throw Error('Generated art has no transparency');
  const output = path.join(root, 'assets/native_art/friends-welcome-v216.webp');
  await sharp(source).resize(512, 512, {fit: 'inside'}).webp({quality: 94, alphaQuality: 100, effort: 6}).toFile(output);
  const {data, info} = await sharp(output).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  let solid = 0;
  let transparent = 0;
  let edgeSolid = 0;
  for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
    const alpha = data[(y * info.width + x) * 4 + 3];
    if (alpha === 0) transparent++;
    if (alpha > 200) {
      solid++;
      if (x < 4 || y < 4 || x >= info.width - 4 || y >= info.height - 4) edgeSolid++;
    }
  }
  if (edgeSolid || transparent < info.width * info.height * .1 || solid < info.width * info.height * .2) {
    throw Error('Art is clipped, lacks transparent margin, or is nearly empty');
  }
  const audit = {source, output, width: info.width, height: info.height, solid, transparent, edgeSolid, bytes: fs.statSync(output).size};
  fs.writeFileSync(path.join(evidence, 'asset-audit.json'), JSON.stringify(audit, null, 2));
  console.log(JSON.stringify(audit));
}
main().catch(error => {console.error(error); process.exitCode = 1;});
