'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {google} = require('googleapis');

const PROJECT = 'luno-chess';
const NUMBER = '955253747543';
const REGION = 'europe-west1';
const DB = 'https://luno-chess-default-rtdb.firebaseio.com';
const AUTH_CONFIG = `https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config`;
const ROOT = path.resolve(__dirname, '../../luno_chess/qa/v217');
const JOURNAL = path.join(ROOT, 'player-reset-journal.json');
const mode = process.argv[2];
if (!['preflight', 'reset', 'resume-reset', 'restore-access'].includes(mode)) throw new Error('Specify preflight, reset, resume-reset or restore-access.');
if (process.env.LUNO_RESET_CONFIRMATION !== 'DELETE_ALL_LUNO_CHESS_PLAYER_DATA') {
  throw new Error('Explicit destructive-operation confirmation is required.');
}
const cliRoot = process.env.LUNO_FIREBASE_CLI_ROOT;
if (!cliRoot) throw new Error('LUNO_FIREBASE_CLI_ROOT is required.');
const firebaseAuth = require(path.join(cliRoot, 'lib/auth.js'));
const account = firebaseAuth.getGlobalDefaultAccount();
if (!account?.tokens?.refresh_token) throw new Error('Firebase CLI login is required.');
const client = new google.auth.OAuth2();
let journal;

const playerPaths = new Set([
  'users', 'publicProfiles', 'presence', 'usernames', 'usernameEmails', 'playerCodes',
  'serverRequests', 'accountLinkTickets', 'serverRateLimits', 'messageThrottle',
  'blocks', 'blockedBy', 'mutes', 'moderationReports', 'deviceTokens', 'rooms',
  'queue', 'matches', 'matchHistory', 'rankedState', 'rankedPlayers',
  'rankedMatchViews', 'rankedReplays', 'rankedMessages', 'friends',
  'friendRequests', 'outgoingFriendRequests', 'matchInvites', 'matchInviteThrottle',
  'socialLocks', 'friendlyRooms', 'friendlyRoomByUser', 'notifications', 'dmInbox',
  'dm', 'matchesV1', 'matchSecretsV1', 'battleV1Control', 'battleV1Accounts',
  'battleV1Ratings', 'auditLogs', 'deletedAccounts', 'accountDeletions',
]);
const protectedPaths = new Set(['battleRollout', 'purchaseClaims', 'billingEvents', 'billingSignals']);

async function request(method, url, data, params) {
  return (await client.request({method, url, data, params, timeout: 30000})).data;
}

function save(phase, fields = {}) {
  Object.assign(journal, fields, {phase, updatedAt: new Date().toISOString()});
  fs.mkdirSync(ROOT, {recursive: true});
  fs.writeFileSync(JOURNAL, `${JSON.stringify(journal, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify({phase, ...fields})}\n`);
}

async function listAccounts() {
  const ids = [];
  let pageToken;
  do {
    const data = await request('GET', `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchGet`, undefined, {
      maxResults: 1000,
      fields: 'users(localId),nextPageToken',
      ...(pageToken ? {nextPageToken: pageToken} : {}),
    });
    for (const user of data.users ?? []) {
      if (typeof user.localId !== 'string' || !user.localId) throw new Error('Invalid Auth account.');
      ids.push(user.localId);
    }
    if (ids.length > 1000) throw new Error('Account count exceeded the reviewed reset safety bound.');
    pageToken = data.nextPageToken;
  } while (pageToken);
  if (new Set(ids).size !== ids.length) throw new Error('Repeated Auth account.');
  return ids;
}

async function rootKeys() {
  const root = await request('GET', `${DB}/.json`, undefined, {shallow: true});
  const keys = Object.keys(root ?? {});
  if (keys.some(key => !playerPaths.has(key) && !protectedPaths.has(key))) {
    throw new Error('An unreviewed database root requires inspection before deletion.');
  }
  return keys;
}

async function signupDisabled(disabled) {
  await request('PATCH', AUTH_CONFIG, {
    name: `projects/${PROJECT}/config`,
    client: {permissions: {disabledUserSignup: disabled}},
  }, {updateMask: 'client.permissions.disabledUserSignup'});
  const result = await request('GET', AUTH_CONFIG);
  if ((result.client?.permissions?.disabledUserSignup === true) !== disabled) {
    throw new Error('Signup gate was not applied.');
  }
}

async function setPublicInvoker(enabled) {
  const base = `https://run.googleapis.com/v2/${journal.apiService}`;
  const policy = await request('GET', `${base}:getIamPolicy`, undefined, {'options.requestedPolicyVersion': 3});
  const bindings = (policy.bindings ?? []).map(binding => ({...binding, members: [...(binding.members ?? [])]}));
  for (const binding of bindings) {
    if (binding.role === 'roles/run.invoker' && !binding.condition) {
      binding.members = binding.members.filter(member => member !== 'allUsers');
    }
  }
  if (enabled) {
    let binding = bindings.find(value => value.role === 'roles/run.invoker' && !value.condition);
    if (!binding) bindings.push(binding = {role: 'roles/run.invoker', members: []});
    binding.members.push('allUsers');
  }
  await request('POST', `${base}:setIamPolicy`, {
    policy: {...policy, bindings: bindings.filter(binding => binding.members.length)},
  });
  const verified = await request('GET', `${base}:getIamPolicy`);
  const publicEnabled = (verified.bindings ?? []).some(binding => binding.role === 'roles/run.invoker' && !binding.condition && binding.members?.includes('allUsers'));
  if (publicEnabled !== enabled) throw new Error('API maintenance gate was not applied.');
}

async function preflight() {
  const keys = await rootKeys();
  const accounts = await listAccounts();
  for (const key of ['purchaseClaims', 'billingEvents', 'billingSignals']) {
    if (keys.includes(key)) throw new Error('Billing records require separate review; this reset does not remove them.');
  }
  const config = await request('GET', AUTH_CONFIG);
  const billing = await request('GET', `https://cloudbilling.googleapis.com/v1/projects/${PROJECT}/billingInfo`);
  if (billing.billingEnabled !== true) throw new Error('Active billing is required before holding access for deployment.');
  const fn = await request('GET', `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/functions/lunoApi`);
  const service = fn.serviceConfig?.service;
  if (typeof service !== 'string' || ![PROJECT, NUMBER].some(id => service.startsWith(`projects/${id}/locations/${REGION}/services/`))) {
    throw new Error('Unexpected API service identity.');
  }
  const timeout = Number(fn.serviceConfig.timeoutSeconds ?? 60);
  if (!Number.isSafeInteger(timeout) || timeout <= 0 || timeout > 300) throw new Error('Unexpected function drain timeout.');
  const runService = await request('GET', `https://run.googleapis.com/v2/${service}`);
  if (runService.invokerIamDisabled === true) throw new Error('Cloud Run invoker checks must be enabled for the maintenance gate.');
  const policy = await request('GET', `https://run.googleapis.com/v2/${service}:getIamPolicy`, undefined, {'options.requestedPolicyVersion': 3});
  const scheduler = await request('GET', `https://cloudscheduler.googleapis.com/v1/projects/${PROJECT}/locations/${REGION}/jobs`, undefined, {pageSize: 100});
  if (scheduler.nextPageToken) throw new Error('Scheduler inventory exceeded the reviewed bound.');
  return {
    projectId: PROJECT,
    projectNumber: NUMBER,
    startedAt: new Date().toISOString(),
    destructiveUserConfirmation: 'Granted in current human message; player accounts and progression only.',
    originalSignupDisabled: config.client?.permissions?.disabledUserSignup === true,
    apiService: service,
    originalPublicInvoker: (policy.bindings ?? []).some(binding => binding.role === 'roles/run.invoker' && !binding.condition && binding.members?.includes('allUsers')),
    jobs: (scheduler.jobs ?? []).map(job => ({name: job.name, originalState: job.state})),
    accountCountBefore: accounts.length,
    drainSeconds: Math.max(timeout, 60) + 15,
    playerRootsBefore: keys.filter(key => playerPaths.has(key)),
    dataBackedUp: false,
  };
}

async function reset(resume = false) {
  if (resume) {
    journal = JSON.parse(fs.readFileSync(JOURNAL, 'utf8'));
    const phases = ['prepared', 'signup-blocked', 'api-in-maintenance', 'scheduler-paused', 'auth-empty', 'draining-in-flight-requests'];
    if (journal.projectId !== PROJECT || journal.projectNumber !== NUMBER || !phases.includes(journal.phase)) {
      throw new Error('Only a partial reset checkpoint may be resumed.');
    }
    await preflight();
  } else {
    if (fs.existsSync(JOURNAL)) throw new Error('A reset journal already exists; use an inspected resume checkpoint.');
    journal = await preflight();
    save('prepared');
  }
  await signupDisabled(true);
  save('signup-blocked');
  await setPublicInvoker(false);
  save('api-in-maintenance');
  for (const job of journal.jobs) {
    if (job.originalState !== 'ENABLED') continue;
    const current = await request('GET', `https://cloudscheduler.googleapis.com/v1/${job.name}`);
    if (current.state === 'ENABLED') await request('POST', `https://cloudscheduler.googleapis.com/v1/${job.name}:pause`, {});
    else if (current.state !== 'PAUSED') throw new Error('An enabled job entered an unexpected state.');
  }
  save('scheduler-paused');

  const currentAccounts = await listAccounts();
  if (currentAccounts.length) {
    const result = await request('POST', `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchDelete`, {
      localIds: currentAccounts,
      force: true,
    });
    if (result.errors?.length) throw new Error(`Auth deletion failed for ${result.errors.length} accounts.`);
  }
  if ((await listAccounts()).length !== 0) throw new Error('Auth is not empty after deletion.');
  save('auth-empty', {accountsDeleted: (journal.accountsDeleted ?? 0) + currentAccounts.length});

  const drainSeconds = journal.drainSeconds;
  if (!Number.isSafeInteger(drainSeconds) || drainSeconds < 75 || drainSeconds > 315) throw new Error('Invalid journal drain bound.');
  save('draining-in-flight-requests', {drainSeconds});
  await new Promise(resolve => setTimeout(resolve, drainSeconds * 1000));

  const deleteKeys = (await rootKeys()).filter(key => playerPaths.has(key));
  if (deleteKeys.length) await request('PATCH', `${DB}/.json`, Object.fromEntries(deleteKeys.map(key => [key, null])), {print: 'silent'});
  const remaining = (await rootKeys()).filter(key => playerPaths.has(key));
  if (remaining.length || (await listAccounts()).length) throw new Error('Reset verification failed.');
  save('reset-verified-held', {accountsAfter: 0, playerRootsAfter: [], rootsDeleted: deleteKeys});
}

async function restoreAccess() {
  journal = JSON.parse(fs.readFileSync(JOURNAL, 'utf8'));
  if (journal.projectId !== PROJECT || journal.projectNumber !== NUMBER || journal.phase !== 'reset-verified-held') {
    throw new Error('A verified reset checkpoint is required before restoring access.');
  }
  const functions = await request('GET', `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/functions`, undefined, {pageSize: 100});
  const required = ['lunoApi', 'sweepRankedMatches', 'sweepBattleV1', 'sweepProductTelemetry', 'playBillingNotifications'];
  const deployed = [];
  for (const id of required) {
    const fn = (functions.functions ?? []).find(value => value.name?.endsWith(`/${id}`));
    if (!fn || fn.state !== 'ACTIVE') throw new Error(`Required function ${id} is not active.`);
    if (Date.parse(fn.updateTime) < Date.parse(journal.startedAt) || !fn.labels?.['firebase-functions-hash']) {
      throw new Error(`Required function ${id} has no fresh deployment evidence.`);
    }
    deployed.push({id, updateTime: fn.updateTime, hash: fn.labels['firebase-functions-hash']});
  }
  await setPublicInvoker(journal.originalPublicInvoker);
  for (const job of journal.jobs) {
    if (job.originalState !== 'ENABLED') continue;
    const current = await request('GET', `https://cloudscheduler.googleapis.com/v1/${job.name}`);
    if (current.state === 'PAUSED') await request('POST', `https://cloudscheduler.googleapis.com/v1/${job.name}:resume`, {});
  }
  await signupDisabled(journal.originalSignupDisabled);
  save('access-restored', {deployedFunctions: deployed});
}

async function main() {
  const session = await firebaseAuth.getAccessToken(account.tokens.refresh_token, []);
  client.setCredentials({access_token: session.access_token, expiry_date: session.expires_at});
  const project = await request('GET', `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}`);
  if (project.projectId !== PROJECT || String(project.projectNumber) !== NUMBER) throw new Error('Project identity mismatch.');
  if (mode === 'preflight') {
    const checked = await preflight();
    process.stdout.write(`${JSON.stringify({ok: true, ...checked}, null, 2)}\n`);
  } else if (mode === 'reset' || mode === 'resume-reset') await reset(mode === 'resume-reset');
  else await restoreAccess();
}

main().catch(error => {
  if (journal) save(journal.phase ?? 'failed', {lastError: error.response?.data?.error?.message ?? error.message});
  process.stderr.write(`${JSON.stringify({ok: false, status: error.response?.status ?? null,
    message: error.response?.data?.error?.message ?? error.message})}\n`);
  process.exitCode = 1;
});
