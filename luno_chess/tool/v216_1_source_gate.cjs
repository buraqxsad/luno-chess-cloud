const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'qa/v216_1/source-freeze.json');
const ignored = new Set(['build', '.gradle', '.cxx', '.kotlin', 'node_modules', 'failures']);
function walk(location) {
  if (!fs.existsSync(location)) return [];
  return fs.readdirSync(location, {withFileTypes: true}).flatMap(entry => {
    if (ignored.has(entry.name)) return [];
    const file = path.join(location, entry.name);
    return entry.isDirectory() ? walk(file) : [file];
  });
}
const files = [
  ...['lib', 'test', 'assets', 'android', 'tool', 'qa/v203-after'].flatMap(dir => walk(path.join(root, dir))),
  ...['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'].map(file => path.join(root, file)),
  path.resolve(root, '../functions/index.js'),
  ...['lib', 'test', 'rules-v1/src', 'rules-v1/test', 'rules-v1/dist'].flatMap(dir => walk(path.resolve(root, '../functions', dir))),
].filter(file => fs.existsSync(file)).sort();
const current = Object.fromEntries(files.map(file => [path.relative(root, file).replaceAll('\\', '/'),
  crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')]));
if (process.argv[2] === 'freeze') {
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, JSON.stringify({createdAt: new Date().toISOString(), files: current}, null, 2));
  console.log(JSON.stringify({action: 'freeze', files: files.length}));
} else {
  const baseline = JSON.parse(fs.readFileSync(output, 'utf8')).files;
  const changed = [...new Set([...Object.keys(baseline), ...Object.keys(current)])]
    .filter(file => baseline[file] !== current[file]);
  const report = {action: 'verify', files: files.length, changed, pass: changed.length === 0};
  fs.writeFileSync(path.join(root, 'qa/v216_1/source-verification.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
  if (changed.length) process.exitCode = 1;
}
