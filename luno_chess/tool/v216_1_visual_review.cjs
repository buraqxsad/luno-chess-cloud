const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const qa = path.join(root, 'qa/v216_1');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');

async function main() {
  const rows = [];
  for (const phase of ['before', 'after']) {
    for (const folder of fs.readdirSync(path.join(qa, phase), {withFileTypes: true})) {
      if (!folder.isDirectory() || ['audio', 'golden-references'].includes(folder.name)) continue;
      const location = path.join(qa, phase, folder.name);
      for (const name of fs.readdirSync(location).filter(name => name.endsWith('.png'))) {
        const file = path.join(location, name);
        const metadata = await sharp(file).metadata();
        const stats = await sharp(file).stats();
        if (stats.channels.slice(0, 3).every(channel => channel.stdev < 2)) throw Error(`Blank render: ${file}`);
        const sidecar = file.replace(/\.png$/, '.json');
        if (fs.existsSync(sidecar)) {
          const record = JSON.parse(fs.readFileSync(sidecar, 'utf8'));
          if (record.logicalViewport) {
            const ratio = folder.name === 'emotes' ? 1 : 2;
            if (metadata.width !== Math.round(record.logicalViewport.width * ratio) ||
                metadata.height !== Math.round(record.logicalViewport.height * ratio)) {
              throw Error(`Viewport/render mismatch: ${file}`);
            }
          }
        }
        rows.push({phase, group: folder.name, name, width: metadata.width, height: metadata.height,
          sha256: hash(fs.readFileSync(file)), rgbStdev: stats.channels.slice(0, 3).map(channel => channel.stdev)});
      }
    }
  }
  const counts = {};
  for (const row of rows) {
    const key = `${row.phase}/${row.group}`;
    counts[key] = (counts[key] || 0) + 1;
  }
  const report = {scope: 'Decode, dimensions and nonblank pixels only; not a subjective visual or device approval',
    counts, renders: rows};
  fs.writeFileSync(path.join(qa, 'visual-render-review.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({counts, total: rows.length, blank: 0, dimensionMismatch: 0}));
}
main().catch(error => {console.error(error); process.exitCode = 1;});
