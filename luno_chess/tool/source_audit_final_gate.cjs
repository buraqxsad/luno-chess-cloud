'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '..'), qa = path.join(root, 'qa');
const json = name => JSON.parse(fs.readFileSync(path.join(qa, name), 'utf8'));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
async function main() {
  const acceptance = json('v201b-acceptance.json');
  assert.equal(acceptance.status, 'V201-B LOCAL ACCEPTANCE PASSED');
  for (const [name, expected] of Object.entries(acceptance.evidenceHashes)) {
    assert.equal(hash(path.join(qa, name)), expected, `Changed evidence: ${name}`);
  }
  for (const [name, expected] of Object.entries(acceptance.sourceHashes)) {
    assert.equal(hash(path.join(root, '..', name)), expected, `Changed source: ${name}`);
  }
  const focused = fs.readFileSync(path.join(qa, 'source-audit-final-focused.txt'), 'utf8');
  assert.match(focused, /\+66: All tests passed!/);
  const android = json('source-audit/android-check.json');
  assert.equal(android.sourceArchiveForbiddenEntries, 0);
  assert.equal(android.debugResourcesWithoutReleaseSigning, true);
  assert.equal(android.releaseWithoutSigningExpectedFailure, true);
  assert.equal(android.presentSigningValidation, true);
  const archive = json('source-audit/package-check.json');
  assert.equal(archive.forbidden, 0);
  assert.equal(hash(path.join(qa, 'source-audit/luno-flutter-source-clean.zip')).toUpperCase(), archive.sha256);
  const strings = json('source-audit/string-inventory.json'), stringCounts = {};
  for (const entry of strings) stringCounts[entry.status] = (stringCounts[entry.status] || 0) + 1;
  assert.equal(stringCounts.VISIBLE_CANDIDATE || 0, 0);
  assert.equal(stringCounts.NATIVE_METADATA_CANDIDATE || 0, 0);
  const assets = json('source-audit/asset-inventory.json');
  assert.equal(assets.launcher.length, 5);
  assert.equal(Object.values(assets.counts).reduce((a, b) => a + b, 0), assets.inventory.length);
  const screens = [];
  const names = ['startup','home','play','collection','profile','missions','shop','settings','friends-empty','battle-initial','battle-after-draw','own-draw-mid','opponent-draw','opponent-public-cards','result','shop-gems'];
  for (const language of ['tr', 'en']) for (const name of names) {
    const relative = `source-audit/screens/${name}-${language}.png`, file = path.join(qa, relative);
    const metadata = await sharp(file).metadata(), stats = await sharp(file).stats();
    assert.equal(metadata.width, 780, relative);
    assert.equal(metadata.height, 1688, relative);
    assert(stats.channels.slice(0, 3).every(channel => channel.stdev > 8), `Blank screenshot: ${relative}`);
    screens.push({file: relative, sha256: hash(file)});
  }
  const report = {
    status: 'SOURCE AUDIT LOCAL GATES PASSED',
    generatedAt: new Date().toISOString(),
    fullFlutterTests: acceptance.flutterTests, focusedTests: 66,
    backendTests: acceptance.backendTests, typeScriptTests: acceptance.typeScriptTests,
    dartPerftChecks: acceptance.dartPerftChecks,
    differentialScenarios: acceptance.differentialScenarios,
    differentialStates: acceptance.differentialStates,
    stringCounts, assetCounts: assets.counts, screenshots: screens,
    sourceArchive: archive, android,
    liveFirebaseVerified: false, physicalAndroidVerified: false,
    liveBillingVerified: false, apkAabGenerated: false, deployed: false,
    notes: ['AST localization and static asset reachability are conservative inventories, not exhaustive runtime proof.', 'A passing local gate is not a guarantee of zero possible bugs or Play acceptance.'],
  };
  fs.writeFileSync(path.join(qa, 'source-audit/final-gate.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({...report, screenshots: screens.length, sourceArchive: {files:archive.files, forbidden:archive.forbidden}}, null, 2));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
