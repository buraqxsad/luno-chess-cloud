'use strict';
const {spawnSync} = require('node:child_process');
require('./helpers/local-emulators').requireLocalEmulators();
if (process.env.GCLOUD_PROJECT !== 'demo-luno-v201b') throw new Error('Demo project required.');
for (const file of ['v201b-security.integration.js', 'v201b-production.integration.js']) {
  const result = spawnSync(process.execPath, [require('node:path').join(__dirname, file)], {stdio: 'inherit', env: process.env});
  if (result.status !== 0) process.exit(result.status ?? 1);
}
