const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '..');
const qa = path.join(root, 'qa');
fs.mkdirSync(qa, { recursive: true });
const walk = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
const protectedRoots = ['lib/engine', 'lib/cards', 'lib/battle_v1', 'lib/models', 'lib/data', 'lib/services', '../functions/rules-v1/src', '../functions/lib', '../battle_contract'];
const files = protectedRoots.flatMap(p => walk(path.resolve(root, p))).filter(p => /\.(dart|ts|js|json)$/.test(p));
files.push(path.resolve(root, '../functions/index.js'), path.resolve(root, '../database.rules.production.json'));
const hashes = Object.fromEntries(files.map(file => [path.relative(root, file).replaceAll('\\', '/'), crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')]));
const baselinePath = path.join(qa, 'v203-protected-baseline.json');
if (process.argv.includes('--baseline')) {
  fs.writeFileSync(baselinePath, JSON.stringify(hashes, null, 2));
  const sources = walk(path.join(root, 'lib')).filter(p => p.endsWith('.dart'));
  const inventory = sources.flatMap(file => [...fs.readFileSync(file, 'utf8').matchAll(/class (\w+(?:Screen|Dialog|Sheet|Setup|Artwork|Gate))\b/g)].map(m => ({ name: m[1], file: path.relative(root, file).replaceAll('\\', '/') })));
  fs.writeFileSync(path.join(qa, 'v203-source-inventory.json'), JSON.stringify(inventory, null, 2));
  console.log(JSON.stringify({ protectedFiles: files.length, surfaces: inventory.length }));
} else {
  const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
  const changed = [...new Set([...Object.keys(baseline), ...Object.keys(hashes)])].filter(k => baseline[k] !== hashes[k]);
  const report = { pass: changed.length === 0, protectedFiles: files.length, changed };
  fs.writeFileSync(path.join(qa, 'v203-protected-check.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
  if (!report.pass) process.exitCode = 1;
}
