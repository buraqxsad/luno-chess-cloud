'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {google} = require('googleapis');

const projectId = 'luno-chess';
const projectNumber = '955253747543';
const appId = '1:955253747543:android:136188eaab561c9b29d812';
const output = process.argv[2] ? path.resolve(process.argv[2]) : null;
const sections = process.argv[3] ? new Set(process.argv[3].split(',')) : null;
const evidenceRoot = path.resolve(__dirname, '../../luno_chess/qa/v217');
if (output && !output.startsWith(evidenceRoot + path.sep)) throw new Error('Evidence output must stay inside qa/v217.');
const cliRoot = process.env.LUNO_FIREBASE_CLI_ROOT;
if (!cliRoot) throw new Error('LUNO_FIREBASE_CLI_ROOT is required.');
const firebaseAuth = require(path.join(cliRoot, 'lib/auth.js'));
const account = firebaseAuth.getGlobalDefaultAccount();
if (!account?.tokens?.refresh_token) throw new Error('Firebase CLI login is required.');
const client = new google.auth.OAuth2();
const results = {projectId, projectNumber, appId, observedAt: new Date().toISOString()};

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}

function sha256(value) {
  return createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
}

async function read(name, url, project) {
  if (sections && !sections.has(name)) return;
  try {
    const response = await client.request({url, method: 'GET', timeout: 30000});
    results[name] = {ok: true, ...project(response.data)};
  } catch (error) {
    results[name] = {
      ok: false,
      status: error.response?.status ?? null,
      message: error.response?.data?.error?.message ?? 'Request failed; credentials are not included.',
    };
  }
}

async function main() {
  const session = await firebaseAuth.getAccessToken(account.tokens.refresh_token, []);
  client.setCredentials({access_token: session.access_token, expiry_date: session.expires_at});
  let billingAccountName = null;
  await read('billing', `https://cloudbilling.googleapis.com/v1/projects/${projectId}/billingInfo`,
    data => {
      billingAccountName = data.billingAccountName ?? null;
      return {billingEnabled: data.billingEnabled === true, accountLinked: Boolean(billingAccountName)};
    });
  if (billingAccountName) {
    await read('billingAccountStatus', `https://cloudbilling.googleapis.com/v1/${billingAccountName}`,
      data => ({open: data.open === true, displayName: data.displayName}));
  }
  await read('billingAccounts', 'https://cloudbilling.googleapis.com/v1/billingAccounts?pageSize=100',
    data => ({accounts: (data.billingAccounts ?? []).map(a => ({
      displayName: a.displayName,
      open: a.open === true,
      linkedToProject: a.name === billingAccountName,
    }))}));
  await read('auth', `https://identitytoolkit.googleapis.com/admin/v2/projects/${projectId}/config`,
    data => ({
      userSignupDisabled: data.client?.permissions?.disabledUserSignup === true,
      anonymous: data.signIn?.anonymous?.enabled === true,
      emailPassword: data.signIn?.email?.enabled === true,
      phone: data.signIn?.phoneNumber?.enabled === true,
      authorizedDomains: data.authorizedDomains ?? [],
      emailEnumerationProtection: data.emailPrivacyConfig?.enableImprovedEmailPrivacy ?? null,
    }));
  await read('storageBuckets', `https://storage.googleapis.com/storage/v1/b?project=${projectId}&projection=noAcl&fields=items(name),nextPageToken&maxResults=100`,
    data => ({buckets: (data.items ?? []).map(value => value.name), paginated: Boolean(data.nextPageToken)}));
  await read('firestoreDatabases', `https://firestore.googleapis.com/v1/projects/${projectId}/databases`,
    data => ({databases: (data.databases ?? []).map(value => ({name: value.name, type: value.type}))}));
  await read('googleSignIn', `https://identitytoolkit.googleapis.com/v2/projects/${projectId}/defaultSupportedIdpConfigs/google.com`,
    data => ({enabled: data.enabled === true}));
  await read('androidApp', `https://firebase.googleapis.com/v1beta1/projects/${projectId}/androidApps/${appId}`,
    data => ({packageName: data.packageName, state: data.state, displayName: data.displayName}));
  await read('androidCertificates', `https://firebase.googleapis.com/v1beta1/projects/${projectId}/androidApps/${appId}/sha`,
    data => ({certificates: (data.certificates ?? []).map(c => ({type: c.certType, shaHash: c.shaHash}))}));
  await read('playIntegrity', `https://firebaseappcheck.googleapis.com/v1beta/projects/${projectNumber}/apps/${appId}/playIntegrityConfig`,
    data => ({
      tokenTtl: data.tokenTtl,
      appIntegrity: data.appIntegrity ?? {},
      deviceIntegrity: data.deviceIntegrity ?? {},
      accountDetails: data.accountDetails ?? {},
    }));
  await read('appCheckServices', `https://firebaseappcheck.googleapis.com/v1/projects/${projectNumber}/services?pageSize=100`,
    data => ({services: (data.services ?? []).map(s => ({name: s.name, enforcementMode: s.enforcementMode}))}));
  await read('functions', `https://cloudfunctions.googleapis.com/v2/projects/${projectId}/locations/europe-west1/functions?pageSize=100`,
    data => ({functions: (data.functions ?? []).map(f => ({
      name: f.name,
      state: f.state,
      updateTime: f.updateTime,
      runtime: f.buildConfig?.runtime,
      entryPoint: f.buildConfig?.entryPoint,
      hash: f.labels?.['firebase-functions-hash'],
      service: f.serviceConfig?.service,
      uri: f.serviceConfig?.uri,
      serviceAccount: f.serviceConfig?.serviceAccountEmail,
      trigger: f.eventTrigger ? {
        eventType: f.eventTrigger.eventType,
        pubsubTopic: f.eventTrigger.pubsubTopic,
        retryPolicy: f.eventTrigger.retryPolicy,
      } : null,
    }))}));
  await read('scheduler', `https://cloudscheduler.googleapis.com/v1/projects/${projectId}/locations/europe-west1/jobs?pageSize=100`,
    data => ({jobs: (data.jobs ?? []).map(j => ({
      name: j.name,
      state: j.state,
      schedule: j.schedule,
      timeZone: j.timeZone,
      lastAttemptTime: j.lastAttemptTime,
      status: j.status ?? null,
      target: j.httpTarget?.uri ?? j.pubsubTarget?.topicName ?? null,
    }))}));
  await read('databaseRules', 'https://luno-chess-default-rtdb.firebaseio.com/.settings/rules.json',
    data => {
      const local = JSON.parse(fs.readFileSync(path.join(__dirname, '../../database.rules.production.json'), 'utf8'));
      if (output) {
        fs.mkdirSync(path.dirname(output), {recursive: true});
        const backup = path.join(path.dirname(output), 'database-rules-live-before.json');
        if (!fs.existsSync(backup)) fs.writeFileSync(backup, `${JSON.stringify(data, null, 2)}\n`, {flag: 'wx'});
      }
      return {
        liveHash: sha256(data),
        localHash: sha256(local),
        identical: sha256(data) === sha256(local),
        rootRead: data.rules?.['.read'],
        rootWrite: data.rules?.['.write'],
        topLevelPaths: Object.keys(data.rules ?? {}).filter(k => !k.startsWith('.')),
        changedTopLevelPaths: [...new Set([...Object.keys(data.rules ?? {}), ...Object.keys(local.rules ?? {})])]
          .filter(key => sha256(data.rules?.[key] ?? null) !== sha256(local.rules?.[key] ?? null)),
      };
    });
  await read('battleRollout', 'https://luno-chess-default-rtdb.firebaseio.com/battleRollout/config.json',
    data => {
      const {validateRollout, LEGACY_ONLY} = require('../rules-v1/dist/src/online/protocol.js');
      const config = data ? validateRollout(data.configJson ? JSON.parse(data.configJson) : data) : {...LEGACY_ONLY};
      return {explicitConfigExists: data !== null, config};
    });
  if (output) {
    fs.mkdirSync(path.dirname(path.resolve(output)), {recursive: true});
    fs.writeFileSync(output, `${JSON.stringify(results, null, 2)}\n`);
  }
  process.stdout.write(`${JSON.stringify(results, null, 2)}\n`);
  if (Object.values(results).some(value => value?.ok === false)) process.exitCode = 1;
}

main().catch(() => {
  process.stderr.write('Live audit failed; credentials and raw responses are not logged.\n');
  process.exitCode = 1;
});
