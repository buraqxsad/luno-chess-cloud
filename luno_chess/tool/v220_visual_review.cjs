'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
sharp.cache(false);
sharp.concurrency(1);

const root = path.resolve(__dirname, '..');
const output = path.join(root, 'qa/v220/visual');
const stages = ['selection', 'cast', 'travel', 'impact', 'persistent', 'cleanup'];
const contract = JSON.parse(fs.readFileSync(path.join(root, '../battle_contract/v1/rules.json'), 'utf8'));
const cards = contract.fixtures.filter(f => /^card-/.test(f.fixtureId))
  .map(f => f.fixtureId.slice(5)).sort();
if (cards.length !== 24 || new Set(cards).size !== 24) throw Error('Expected 24 unique card fixtures');
fs.mkdirSync(output, {recursive: true});
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const writeJson = (file, data) => fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');

async function hash(file) {
  const digest = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) digest.update(chunk);
  return digest.digest('hex');
}

function filesIn(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    if (entry.isSymbolicLink()) return [];
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? filesIn(file) : [file];
  });
}

async function snapshot() {
  const files = [
    ...filesIn(path.join(root, 'lib')),
    ...filesIn(path.join(root, 'assets')),
    path.join(root, 'test/v220_visual_spells_test.dart'),
    path.join(root, 'test/battle_ui/visual_test.dart'),
    path.join(root, 'test/battle_practice_v208_test.dart'),
    path.join(root, 'test/helpers/battle_v1_response.dart'),
    path.join(root, 'tool/battle_fixture_support.dart'),
    path.join(root, 'tool/v220_visual_review.cjs'),
    path.join(root, '../battle_contract/v1/rules.json'),
    path.join(root, 'pubspec.yaml'), path.join(root, 'pubspec.lock'),
  ].sort();
  const hashes = {};
  for (const file of files) hashes[path.relative(root, file).replaceAll('\\', '/')] = await hash(file);
  return hashes;
}

async function inspect(file, expected) {
  const metadata = await sharp(file, {limitInputPixels: 10000000}).metadata();
  const statistics = await sharp(file, {limitInputPixels: 10000000}).stats();
  if (!metadata.width || !metadata.height || statistics.channels.every(c => c.stdev < 1)) {
    throw Error(`Invalid/blank PNG: ${file}`);
  }
  const sha256 = await hash(file);
  if (expected && (metadata.width !== expected.width || metadata.height !== expected.height ||
      sha256 !== expected.sha256)) throw Error(`V219 archive mismatch: ${file}`);
  return {width: metadata.width, height: metadata.height, sha256};
}

async function baseline() {
  const archive = path.join(root, 'qa/v219/after');
  const manifest = readJson(path.join(archive, 'render-manifest.json'));
  if (manifest.renders.length !== 448 || manifest.contacts.length !== 61) {
    throw Error('V219 historical manifest count differs from 448/61');
  }
  const renders = [];
  for (const entry of manifest.renders) {
    const file = path.join(archive, 'screens', entry.file);
    renders.push({file: entry.file, ...await inspect(file, entry)});
  }
  const contacts = [];
  for (const entry of manifest.contacts) {
    const file = path.join(archive, 'contacts', entry.file);
    contacts.push({file: entry.file, renders: entry.renders, ...await inspect(file)});
  }
  const report = {checkedAt: new Date().toISOString(),
    method: 'Sequential PNG decoding/nonblank/dimension/SHA-256 checks of historical V219 archive; no SDK or live app',
    historicalEvidenceOnly: true, personallyViewed: 'See REVIEW.md; machine checks are not personal visual inspection',
    renders, contacts};
  writeJson(path.join(output, 'v219-archive-machine-check.json'), report);
  console.log(JSON.stringify({historicalRendersVerified: renders.length, contactSheetsChecked: contacts.length}));
}

async function prepare() {
  writeJson(path.join(output, 'prepared-source.json'), {
    recordedAt: new Date().toISOString(), method: 'SHA-256 current Flutter runtime/assets and presentation harness inputs',
    files: await snapshot(),
  });
  writeJson(path.join(output, 'matrix.json'), {
    status: 'PREPARED_NOT_EXECUTED', cards, viewers: ['white', 'black'], motion: ['normal', 'reduced'],
    cases: 96, stages, expectedFrames: 576, viewport: {width: 390, height: 844},
    sourceEvidence: 'prepared-source.json',
    notVerified: ['Flutter compilation/test results', 'actual V220 renders', 'Android device', 'emulator', 'live backend', 'native audio', 'FPS/RAM/thermals'],
    guard: 'Do not start render until parent explicitly says Android build complete and grants serialized SDK slot',
  });
  console.log('Prepared 96 actual-screen cases / 576 frames; no Flutter or Dart SDK launched.');
}

async function render() {
  if (process.env.V220_PARENT_BUILD_COMPLETE !== '1') {
    throw Error('SDK execution blocked. Parent must explicitly confirm build complete; then set V220_PARENT_BUILD_COMPLETE=1.');
  }
  const runDirectory = path.join(output, 'runs', new Date().toISOString().replaceAll(':', '-'));
  fs.mkdirSync(runDirectory, {recursive: true});
  writeJson(path.join(output, 'last-run.json'), {directory: path.relative(output, runDirectory)});
  const start = {startedAt: new Date().toISOString(), files: await snapshot()};
  writeJson(path.join(runDirectory, 'run-start.json'), start);
  const flutter = process.env.V220_FLUTTER || 'L:\\.tools\\flutter\\bin\\flutter.bat';
  if (!fs.existsSync(flutter)) throw Error(`Existing Flutter SDK path unavailable: ${flutter}`);
  const command = `& '${flutter.replaceAll("'", "''")}' test --no-pub --concurrency=1 --reporter expanded test/v220_visual_spells_test.dart`;
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], {
    cwd: root, env: {...process.env, CI: 'true', V220_CAPTURE_ACTUAL: '1'},
    encoding: 'utf8', windowsHide: true, timeout: 15 * 60 * 1000, maxBuffer: 16 * 1024 * 1024,
  });
  fs.writeFileSync(path.join(runDirectory, 'flutter-stdout.txt'), result.stdout || '');
  fs.writeFileSync(path.join(runDirectory, 'flutter-stderr.txt'), result.stderr || '');
  writeJson(path.join(runDirectory, 'run-result.json'), {command, completedAt: new Date().toISOString(),
    exitCode: result.status, error: result.error?.message || null, signal: result.signal || null});
  console.log(JSON.stringify({exitCode: result.status, error: result.error?.message || null}));
  if (result.status !== 0 || result.error) {
    process.exitCode = 1;
    return;
  }
  await archive();
}

async function archive() {
  const runDirectory = path.join(output, readJson(path.join(output, 'last-run.json')).directory);
  const start = readJson(path.join(runDirectory, 'run-start.json'));
  const result = readJson(path.join(runDirectory, 'run-result.json'));
  if (result.exitCode !== 0 || result.error) throw Error('Cannot archive an unsuccessful run as a pass');
  const current = await snapshot();
  const mutations = [...new Set([...Object.keys(start.files), ...Object.keys(current)])]
    .filter(file => start.files[file] !== current[file]);
  if (mutations.length) throw Error(`Runtime/assets/harness changed during capture: ${mutations.join(', ')}`);
  const frames = [];
  const sheets = [];
  fs.mkdirSync(path.join(output, 'contacts'), {recursive: true});
  for (const card of cards) for (const viewer of ['white', 'black']) for (const motion of ['normal', 'reduced']) {
    const tag = `${card}-${viewer}-${motion}`;
    const tiles = [];
    for (const [index, stage] of stages.entries()) {
      const file = path.join(output, 'frames', tag, `${stage}.png`);
      const data = readJson(file.replace(/\.png$/, '.json'));
      if (fs.statSync(file).mtimeMs < Date.parse(start.startedAt) || data.card !== card ||
          data.viewer !== viewer || data.stage !== stage || data.reducedMotion !== (motion === 'reduced') ||
          data.physicalDevice !== false || data.liveBackend !== false) {
        throw Error(`Stale/mismatched frame metadata: ${file}`);
      }
      const image = await inspect(file);
      if (image.width !== 390 || image.height !== 844) throw Error(`Unexpected viewport: ${file}`);
      frames.push({file: path.relative(output, file).replaceAll('\\', '/'), ...image, metadata: data});
      const label = Buffer.from(`<svg width="195" height="24"><rect width="195" height="24" fill="#080f18"/><text x="6" y="17" font-family="Arial" font-size="12" fill="white">${stage} ${data.elapsedPresentationMs}ms</text></svg>`);
      const thumb = await sharp(file).resize(195, 422).png().toBuffer();
      tiles.push({input: label, left: index * 195, top: 0}, {input: thumb, left: index * 195, top: 24});
    }
    const name = `${tag}.png`;
    await sharp({create: {width: 1170, height: 446, channels: 4, background: '#080f18'}})
      .composite(tiles).png().toFile(path.join(output, 'contacts', name));
    sheets.push({file: `contacts/${name}`, frames: stages.map(stage => `frames/${tag}/${stage}.png`)});
  }
  writeJson(path.join(output, 'render-manifest.json'), {
    checkedAt: new Date().toISOString(), method: 'Actual native BattleV1Screen Flutter widget renders; authoritative transport mocked; no Android/device/live evidence',
    sourceStableDuringRun: true, sourceEvidence: path.relative(output, path.join(runDirectory, 'run-start.json')).replaceAll('\\', '/'), frames, contacts: sheets,
    personallyViewed: 'Only frames explicitly listed in REVIEW.md were personally viewed',
  });
  console.log(JSON.stringify({actualWidgetFrames: frames.length, contactSheets: sheets.length, sourceStableDuringRun: true}));
}

async function overview() {
  const manifest = readJson(path.join(output, 'render-manifest.json'));
  const run = path.join(output, readJson(path.join(output, 'last-run.json')).directory);
  const start = readJson(path.join(run, 'run-start.json'));
  const result = readJson(path.join(run, 'run-result.json'));
  if (result.exitCode !== 0 || result.error || manifest.frames.length !== 576) {
    throw Error('Overview requires the completed successful 576-frame run');
  }
  const directory = path.join(output, 'overviews');
  fs.mkdirSync(directory, {recursive: true});
  const sheets = [];
  for (const viewer of ['white', 'black']) {
    const selected = cards.map(card => manifest.frames.find(frame =>
      frame.metadata.card === card && frame.metadata.viewer === viewer &&
      frame.metadata.stage === 'impact' && !frame.metadata.reducedMotion));
    if (selected.some(frame => !frame)) throw Error(`Missing normal impact for ${viewer}`);
    for (let page = 0; page < 2; page++) {
      const tiles = [];
      const frames = selected.slice(page * 12, page * 12 + 12);
      for (const [index, frame] of frames.entries()) {
        const file = path.join(output, frame.file);
        await inspect(file, frame);
        const left = index % 4 * 260, top = Math.floor(index / 4) * 393;
        const label = Buffer.from(`<svg width="260" height="26"><rect width="260" height="26" fill="#080f18"/><text x="6" y="18" font-family="Arial" font-size="13" fill="white">${frame.metadata.card} ${frame.metadata.elapsedPresentationMs}ms</text></svg>`);
        // Crop only the overview: keep each original 390x844 frame untouched.
        const thumb = await sharp(file).extract({left: 0, top: 0, width: 390, height: 550})
          .resize(260, 367).png().toBuffer();
        tiles.push({input: label, left, top}, {input: thumb, left, top: top + 26});
      }
      const name = `all24-normal-impact-${viewer}-${page + 1}.png`;
      const file = path.join(directory, name);
      await sharp({create: {width: 1040, height: 1179, channels: 4, background: '#080f18'}})
        .composite(tiles).png().toFile(file);
      sheets.push({file: `overviews/${name}`, viewer, frames: frames.map(frame => frame.file),
        crop: {left: 0, top: 0, width: 390, height: 550}, ...await inspect(file)});
    }
  }
  const current = await snapshot();
  const changed = [...new Set([...Object.keys(start.files), ...Object.keys(current)])]
    .filter(file => start.files[file] !== current[file]);
  const expectedOfflineToolChange = changed.filter(file => file === 'tool/v220_visual_review.cjs');
  const independentBillingChange = changed.filter(file => file === 'lib/services/luno_billing_service.dart');
  const otherInputChanges = changed.filter(file => !expectedOfflineToolChange.includes(file) &&
    !independentBillingChange.includes(file));
  const proof = {checkedAt: new Date().toISOString(), runStart: start.startedAt,
    runCompleted: result.completedAt, runExitCode: result.exitCode,
    captureSourceStableDuringRun: manifest.sourceStableDuringRun,
    hashedInputCount: Object.keys(start.files).length,
    scope: 'All Flutter lib files, all assets, six presentation/helper inputs, contract and pubspec/lock; no backend, Android generated artifacts, signing or production data',
    expectedOfflineToolChange, independentBillingChange, otherInputChanges,
    currentVisualInputsUnchanged: otherInputChanges.length === 0,
    note: 'The optional billing-service delta belongs to the authorized independent restore fix and was not exercised by the injected BattleV1Screen transport. This is a visual-input check, not the parent whole-source freeze.',
    changedHashes: changed.map(file => ({file, atCapture: start.files[file] || null, now: current[file] || null})),
  };
  writeJson(path.join(output, 'postprocess-source-verification.json'), proof);
  writeJson(path.join(output, 'overview-manifest.json'), {
    method: 'Offline contact composition from hash-verified successful actual widget impact PNGs; no SDK rerun, image regeneration or runtime/art change',
    inspectedScope: '24 normal-motion impacts per viewer, cropped scaled overview only; not every pixel or animation frame',
    sheets,
  });
  const matrix = readJson(path.join(output, 'matrix.json'));
  writeJson(path.join(output, 'matrix.json'), {...matrix,
    status: 'FOCUSED_PASS_97_ACTUAL_WIDGET_TESTS', actualFrames: 576, actualSequenceContacts: 96,
    overviewContacts: sheets.length, sourceEvidence: manifest.sourceEvidence,
    successfulRun: path.relative(output, run).replaceAll('\\', '/'),
    notVerified: ['parent full-final regression/freeze', 'Android device', 'emulator', 'live backend', 'native audio', 'FPS/RAM/thermals'],
  });
  console.log(JSON.stringify({overviewSheets: sheets.length, normalImpactFramesCovered: 48,
    hashedInputCount: proof.hashedInputCount, expectedOfflineToolChange, independentBillingChange,
    otherInputChanges, currentVisualInputsUnchanged: proof.currentVisualInputsUnchanged}));
}

const modes = {baseline, prepare, render, archive, overview};
const mode = process.argv[2];
if (!Object.hasOwn(modes, mode)) throw Error('Use baseline, prepare, render, archive, or overview');
modes[mode]().catch(error => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
