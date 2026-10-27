'use strict';
const {requireLocalEmulators} = require('./helpers/local-emulators');
requireLocalEmulators();
if (process.env.GCLOUD_PROJECT !== 'demo-luno-v201b') {
  throw new Error('The acceptance fixtures require demo-luno-v201b.');
}
process.env.LUNO_DB_EMULATOR_NAMESPACE = 'demo-luno-v201b-default-rtdb';
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const qa = path.resolve(__dirname, '../../luno_chess/qa/v215');
fs.mkdirSync(qa, {recursive: true});
const checks = [
  ['v201b-security.integration.js', 'v201b-gate1-security.json', 'gate1-security.json'],
  ['v201b-production.integration.js', 'v201b-gate5-production.json', 'gate5-production.json'],
  ['v214-social-safety.integration.js'],
  ['v215-economy.integration.js'],
];
for (const [script, from, to] of checks) {
  const result = spawnSync(process.execPath, [path.join(__dirname, script)], {
    env: process.env, encoding: 'utf8', timeout: 180000,
  });
  fs.writeFileSync(path.join(qa, `${script}.txt`),
    (result.stdout || '') + (result.stderr || ''));
  if (result.status !== 0) {
    process.stderr.write(`${script} failed: ${result.error || result.status}\n${result.stderr || ''}`);
    process.exit(1);
  }
  if (from) fs.copyFileSync(path.resolve(qa, '..', from), path.join(qa, to));
  process.stdout.write(`${script}: passed\n`);
}
