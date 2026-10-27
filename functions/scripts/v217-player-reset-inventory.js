'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {google} = require('googleapis');

const projectId = 'luno-chess';
const projectNumber = '955253747543';
const databaseUrl = 'https://luno-chess-default-rtdb.firebaseio.com';
const cliRoot = process.env.LUNO_FIREBASE_CLI_ROOT;
if (!cliRoot) throw new Error('LUNO_FIREBASE_CLI_ROOT is required.');
const firebaseAuth = require(path.join(cliRoot, 'lib/auth.js'));
const account = firebaseAuth.getGlobalDefaultAccount();
if (!account?.tokens?.refresh_token) throw new Error('Firebase CLI login is required.');
const client = new google.auth.OAuth2();
const output = path.resolve(process.argv[2] ?? '../luno_chess/qa/v217/player-reset-inventory.json');
const evidenceRoot = path.resolve(__dirname, '../../luno_chess/qa/v217');
if (!output.startsWith(evidenceRoot + path.sep)) throw new Error('Evidence must stay inside qa/v217.');

const protectedPaths = new Set(['battleRollout']);
const operationalPaths = new Set(['battleV1Maintenance']);
const receiptPaths = new Set(['purchaseClaims', 'billingEvents', 'billingSignals', 'auditLogs', 'deletedAccounts', 'accountDeletions']);
const playerPaths = new Set([
  'users', 'publicProfiles', 'presence', 'usernames', 'playerCodes', 'serverRequests',
  'accountLinkTickets', 'serverRateLimits', 'messageThrottle', 'blocks', 'blockedBy',
  'mutes', 'moderationReports', 'deviceTokens', 'rooms', 'queue', 'matches',
  'matchHistory', 'rankedState', 'rankedPlayers', 'rankedMatchViews', 'rankedReplays',
  'rankedMessages', 'friends', 'friendRequests', 'outgoingFriendRequests',
  'matchInvites', 'matchInviteThrottle', 'socialLocks', 'friendlyRooms',
  'friendlyRoomByUser', 'notifications', 'dmInbox', 'dm', 'matchesV1',
  'matchSecretsV1', 'battleV1Control', 'battleV1Accounts', 'battleV1Ratings',
]);

async function get(url, params) {
  const response = await client.request({url, method: 'GET', params, timeout: 30000});
  return response.data;
}

async function main() {
  const session = await firebaseAuth.getAccessToken(account.tokens.refresh_token, []);
  client.setCredentials({access_token: session.access_token, expiry_date: session.expires_at});
  const project = await get(`https://firebase.googleapis.com/v1beta1/projects/${projectId}`);
  if (project.projectId !== projectId || String(project.projectNumber) !== projectNumber) {
    throw new Error('Project identity mismatch.');
  }

  const auth = {count: 0, disabled: 0, providers: {}, pages: 0};
  const uidSet = new Set();
  let pageToken;
  do {
    const data = await get(`https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:batchGet`, {
      maxResults: 1000,
      ...(pageToken ? {nextPageToken: pageToken} : {}),
      fields: 'users(localId,providerUserInfo(providerId),disabled),nextPageToken',
    });
    for (const user of data.users ?? []) {
      if (!user.localId || uidSet.has(user.localId)) throw new Error('Invalid or repeated Auth account.');
      uidSet.add(user.localId);
      auth.count++;
      if (user.disabled) auth.disabled++;
      const providers = user.providerUserInfo?.map(provider => provider.providerId) ?? [];
      for (const provider of providers.length ? providers : ['anonymous']) {
        auth.providers[provider] = (auth.providers[provider] ?? 0) + 1;
      }
    }
    pageToken = data.nextPageToken;
    if (++auth.pages > 10000) throw new Error('Auth inventory page limit exceeded.');
  } while (pageToken);
  auth.uidSetDigest = createHash('sha256').update(JSON.stringify([...uidSet].sort())).digest('hex');

  const root = await get(`${databaseUrl}/.json`, {shallow: true});
  const database = [];
  for (const key of Object.keys(root ?? {}).sort()) {
    const data = await get(`${databaseUrl}/${encodeURIComponent(key)}.json`, {shallow: true});
    database.push({
      path: key,
      immediateChildren: data && typeof data === 'object' ? Object.keys(data).length : data === null ? 0 : 1,
      category: protectedPaths.has(key) ? 'configuration' : operationalPaths.has(key) ? 'server-maintenance-state' : receiptPaths.has(key) ? 'billing-security-records' : playerPaths.has(key) ? 'player-data' : 'review-before-any-reset',
    });
  }
  const result = {
    projectId,
    projectNumber,
    observedAt: new Date().toISOString(),
    readOnly: true,
    auth,
    database,
    note: 'Counts are a live inventory, not a transactional snapshot. No emails, usernames, UIDs, messages, passwords, tokens or payment details are exported.',
  };
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch(error => {
  process.stderr.write(`${JSON.stringify({
    ok: false,
    status: error.response?.status ?? null,
    message: error.response?.data?.error?.message ?? 'Read-only inventory failed; raw responses and credentials are not logged.',
  })}\n`);
  process.exitCode = 1;
});
