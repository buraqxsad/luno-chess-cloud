'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {google} = require('googleapis');
const {validateRollout, LEGACY_ONLY} = require('../rules-v1/dist/src/online/protocol.js');

const PROJECT = 'luno-chess';
const NUMBER = '955253747543';
const REGION = 'europe-west1';
const CONFIG_URL = 'https://luno-chess-default-rtdb.firebaseio.com/battleRollout/config.json';
const root = path.resolve(__dirname, '../../luno_chess/qa/v217');
const journal = JSON.parse(fs.readFileSync(path.join(root, 'player-reset-journal.json'), 'utf8'));
if (journal.projectId !== PROJECT || journal.projectNumber !== NUMBER || journal.phase !== 'reset-verified-held') {
  throw new Error('A held verified player reset is required before this rollout.');
}
const cliRoot = process.env.LUNO_FIREBASE_CLI_ROOT;
if (!cliRoot) throw new Error('LUNO_FIREBASE_CLI_ROOT is required.');
const firebaseAuth = require(path.join(cliRoot, 'lib/auth.js'));
const account = firebaseAuth.getGlobalDefaultAccount();
const client = new google.auth.OAuth2();

async function main() {
  if (!account?.tokens?.refresh_token) throw new Error('Firebase CLI login is required.');
  const session = await firebaseAuth.getAccessToken(account.tokens.refresh_token, []);
  client.setCredentials({access_token: session.access_token, expiry_date: session.expires_at});
  const project = (await client.request({url: `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}`, timeout: 30000})).data;
  if (project.projectId !== PROJECT || String(project.projectNumber) !== NUMBER) throw new Error('Project identity mismatch.');
  const deployed = (await client.request({url: `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/functions?pageSize=100`, timeout: 30000})).data;
  const required = ['lunoApi', 'sweepRankedMatches', 'sweepBattleV1', 'sweepProductTelemetry', 'playBillingNotifications'];
  const functions = required.map(id => {
    const fn = (deployed.functions ?? []).find(value => value.name?.endsWith(`/${id}`));
    if (!fn || fn.state !== 'ACTIVE' || !fn.labels?.['firebase-functions-hash'] || !(Date.parse(fn.updateTime) >= Date.parse(journal.startedAt))) {
      throw new Error(`Fresh active deployment is required for ${id}.`);
    }
    return {id, hash: fn.labels['firebase-functions-hash'], updateTime: fn.updateTime};
  });
  const response = await client.request({url: CONFIG_URL, headers: {'X-Firebase-ETag': 'true'}, timeout: 30000});
  const current = response.data;
  const before = current ? validateRollout(current.configJson ? JSON.parse(current.configJson) : current) : {...LEGACY_ONLY};
  if (current?.configJson && current.configVersion !== before.configVersion) throw new Error('Inconsistent rollout version.');
  if (before.legacyForceUpdateEnabled || before.forceUpdatePlatforms.length || !before.legacyNewMatchesEnabled) {
    throw new Error('Existing force-update policy requires explicit review, not overwriting.');
  }
  const next = validateRollout({...before, configVersion: before.configVersion + 1,
    v1MatchmakingEnabled: true, maintenanceMode: false});
  const etag = response.headers.get?.('etag') ?? response.headers.etag;
  if (typeof etag !== 'string' || !etag) throw new Error('Conditional-write ETag is required.');
  await client.request({method: 'PUT', url: CONFIG_URL, headers: {'if-match': etag}, timeout: 30000,
    data: {configVersion: next.configVersion, configJson: JSON.stringify(next)}});
  const verified = (await client.request({url: CONFIG_URL, timeout: 30000})).data;
  if (JSON.stringify(validateRollout(JSON.parse(verified.configJson))) !== JSON.stringify(next) || verified.configVersion !== next.configVersion) {
    throw new Error('Rollout read-back did not match.');
  }
  const evidence = {projectId: PROJECT, projectNumber: NUMBER, observedAt: new Date().toISOString(),
    conditionalWrite: true, functions, before, after: next, verified: true,
    playInstalledTwoClientAcceptance: 'NOT TESTED'};
  fs.writeFileSync(path.join(root, 'firebase-v1-rollout-enabled.json'), `${JSON.stringify(evidence, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
}

main().catch(error => {
  process.stderr.write(`${JSON.stringify({ok: false, status: error.response?.status ?? null,
    message: error.response?.data?.error?.message ?? error.message})}\n`);
  process.exitCode = 1;
});
