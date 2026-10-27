const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

sharp('art-source/v211/battle-card-face.png')
  .resize(360, 480, { fit: 'fill' })
  .webp({ quality: 90, effort: 6 })
  .toFile('assets/native_art/battle-card-face-v211.webp')
  .then(result => console.log(JSON.stringify(result)))
  .catch(error => { console.error(error); process.exitCode = 1; });
