const fs = require('fs'), path = require('path');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const phase = process.argv[2] || 'before';
if (!['before', 'after', 'battle'].includes(phase)) throw new Error('Invalid capture phase');
const dir = phase === 'battle' ? path.join(root, 'test/battle_ui/goldens') : path.join(root, 'qa', `v203-${phase}`);
const names = fs.readdirSync(dir).filter(f => f.endsWith('.png')).sort();
(async () => {
  const output = path.join(root, 'qa', `v203-${phase}-contact`);
  fs.mkdirSync(output, { recursive: true });
  for (let page = 0; page < Math.ceil(names.length / 8); page++) {
    const composites = [];
    for (const [i, name] of names.slice(page * 8, page * 8 + 8).entries()) {
      const left = (i % 4) * 210, top = Math.floor(i / 4) * 478;
      composites.push({ input: await sharp(path.join(dir, name)).resize(195, 422, { fit: 'contain', background: '#080f18' }).png().toBuffer(), left: left + 7, top: top + 30 });
      const label = `<svg width="210" height="28"><text x="8" y="20" font-family="Arial" font-size="14" fill="white">${name.replace('.png', '')}</text></svg>`;
      composites.push({ input: Buffer.from(label), left, top });
    }
    await sharp({ create: { width: 840, height: 956, channels: 4, background: '#18232e' } }).composite(composites).png().toFile(path.join(output, `page-${page + 1}.png`));
  }
  console.log(JSON.stringify({ phase, screenshots: names.length, pages: Math.ceil(names.length / 8) }));
})();
