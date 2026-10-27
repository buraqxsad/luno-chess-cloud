const path = require('node:path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const input = 'C:/Users/Casper/.codex/generated_images/019f5d34-6fc3-71e1-b469-b9e0da8eb51c/exec-2df63ade-b9fa-49f6-8465-c28a43073b77.png';
sharp(input).resize(360, 480, { fit: 'fill' }).webp({ quality: 90 })
  .toFile(path.join(__dirname, '..', 'assets', 'native_art', 'battle-card-face-v210.webp'))
  .then(info => process.stdout.write(JSON.stringify(info) + '\n'))
  .catch(error => { console.error(error); process.exitCode = 1; });
