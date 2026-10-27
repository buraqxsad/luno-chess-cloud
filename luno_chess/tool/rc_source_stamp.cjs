const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const backend = path.resolve(root, '../functions');
const repository = path.dirname(root);
const destination = process.argv[3]
  ? path.resolve(root, process.argv[3]) : path.join(root, 'qa/rc/source-lock.json');
if (!destination.startsWith(path.join(root, 'qa') + path.sep) || !destination.endsWith('.json')) {
  throw new Error('Source lock destination must be a JSON file inside workspace qa.');
}
const mode = process.argv[2] || 'verify';

function filesIn(directory, accept) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    if (entry.isSymbolicLink()) return [];
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? filesIn(file, accept) : accept(file) ? [file] : [];
  });
}

function snapshot() {
  const files = [
    ...filesIn(path.join(root, 'lib'), file => file.endsWith('.dart')),
    ...filesIn(path.join(root, 'test'), file => file.endsWith('.dart') ||
      (file.endsWith('.png') && file.split(path.sep).includes('goldens'))),
    ...filesIn(path.join(root, 'qa/v203-after'), file => file.endsWith('.png')),
    ...filesIn(path.join(root, 'tool'), file => /\.(dart|cjs|ps1|py|java)$/.test(file)),
    ...filesIn(path.join(root, 'assets'), () => true),
    ...filesIn(path.join(root, 'android/app/src/main'), file => /\.(xml|kt|png|webp)$/.test(file)),
    ...filesIn(path.join(backend, 'src'), file => file.endsWith('.ts')),
    ...filesIn(path.join(backend, 'lib'), file => file.endsWith('.js')),
    ...filesIn(path.join(backend, 'test'), file => file.endsWith('.js')),
    ...filesIn(path.join(backend, 'tools'), file => /\.(js|cjs|ts)$/.test(file)),
    ...filesIn(path.join(backend, 'rules-v1/src'), file => file.endsWith('.ts')),
    ...filesIn(path.join(backend, 'rules-v1/dist/src'), file => file.endsWith('.js')),
    ...filesIn(path.join(backend, 'rules-v1/test'), file => /\.(ts|json)$/.test(file)),
    ...filesIn(path.join(backend, 'rules-v1/fixtures'), file => file.endsWith('.json')),
    ...filesIn(path.join(repository, 'battle_contract/v1'), file => file.endsWith('.json')),
    ...filesIn(path.resolve(root, '../../luno-legal-site'), file =>
      /\.(html|css|json)$/.test(file) && !file.split(path.sep).includes('.vercel')),
    ...['index.js', 'package.json', 'package-lock.json',
      'rules-v1/package.json', 'rules-v1/tsconfig.json'].map(file => path.join(backend, file)),
    ...['database.rules.production.json', 'firebase.emulators.v201b.json',
      'firebase.json'].map(file => path.join(repository, file)),
    ...['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'android/app/build.gradle.kts',
      'android/build.gradle.kts', 'android/settings.gradle.kts',
      'android/gradle.properties', 'android/app/google-services.json',
      'android/gradle/wrapper/gradle-wrapper.properties',
      'android/gradlew', 'android/gradlew.bat', '.gitignore', 'android/.gitignore'].map(file => path.join(root, file)),
  ];
  return Object.fromEntries([...new Set(files)].sort().map(file => [
    path.relative(root, file).replaceAll('\\', '/'),
    crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),
  ]));
}

const current = snapshot();
if (mode === 'record') {
  fs.mkdirSync(path.dirname(destination), {recursive: true});
  fs.writeFileSync(destination, JSON.stringify({
    recordedAt: new Date().toISOString(),
    method: 'SHA-256 production Flutter, tests and golden PNGs, assets, battle contracts, Android main resources/config, backend source; no credentials or local keystore included',
    files: current,
  }, null, 2) + '\n');
  console.log(`Recorded ${Object.keys(current).length} source/test/asset hashes.`);
} else if (mode === 'verify') {
  const previous = JSON.parse(fs.readFileSync(destination, 'utf8')).files;
  const changed = [...new Set([...Object.keys(previous), ...Object.keys(current)])]
    .filter(file => previous[file] !== current[file]);
  console.log(JSON.stringify({files: Object.keys(current).length, changed}));
  if (changed.length) process.exitCode = 1;
} else {
  throw new Error(`Unknown source stamp mode: ${mode}`);
}
