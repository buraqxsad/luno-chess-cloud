'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {google}=require('googleapis');
const PROJECT='luno-chess';
const NUMBER='955253747543';
const REGION='europe-west1';
const root=path.resolve(__dirname,'../../luno_chess/qa/v217');
const cliRoot=process.env.LUNO_FIREBASE_CLI_ROOT;
if(!cliRoot)throw new Error('LUNO_FIREBASE_CLI_ROOT is required.');
const firebaseAuth=require(path.join(cliRoot,'lib/auth.js'));
const account=firebaseAuth.getGlobalDefaultAccount();
const client=new google.auth.OAuth2();
const ids=['sweepRankedMatches','sweepBattleV1','sweepProductTelemetry'];
const names=ids.map(id=>`projects/${PROJECT}/locations/${REGION}/jobs/firebase-schedule-${id}-${REGION}`);
const evidence={projectId:PROJECT,startedAt:new Date().toISOString(),jobs:[],passed:false};
const request=async(method,url)=>(await client.request({method,url,timeout:30000})).data;

async function main(){
  if(!account?.tokens?.refresh_token)throw new Error('Firebase CLI login is required.');
  const session=await firebaseAuth.getAccessToken(account.tokens.refresh_token,[]);
  client.setCredentials({access_token:session.access_token,expiry_date:session.expires_at});
  const project=await request('GET',`https://firebase.googleapis.com/v1beta1/projects/${PROJECT}`);
  if(project.projectId!==PROJECT||String(project.projectNumber)!==NUMBER)throw new Error('Project identity mismatch.');
  for(const name of names){
    const job=await request('GET',`https://cloudscheduler.googleapis.com/v1/${name}`);
    if(job.state!=='ENABLED')throw new Error('A required scheduler job is not enabled.');
    await request('POST',`https://cloudscheduler.googleapis.com/v1/${name}:run`);
  }
  const deadline=Date.now()+90000;
  while(Date.now()<deadline){
    const jobs=[];
    for(const name of names){
      const value=await request('GET',`https://cloudscheduler.googleapis.com/v1/${name}`);
      const status=value.status?.code??0;
      jobs.push({name,state:value.state,lastAttemptTime:value.lastAttemptTime??null,statusCode:status,
        fresh:Date.parse(value.lastAttemptTime)>=Date.parse(evidence.startedAt)});
    }
    evidence.jobs=jobs;
    if(jobs.every(value=>value.state==='ENABLED'&&value.fresh&&value.statusCode===0)){
      evidence.passed=true;
      evidence.completedAt=new Date().toISOString();
      fs.writeFileSync(path.join(root,'firebase-live-scheduler-smoke.json'),`${JSON.stringify(evidence,null,2)}\n`);
      process.stdout.write(`${JSON.stringify(evidence,null,2)}\n`);
      return;
    }
    await new Promise(resolve=>setTimeout(resolve,5000));
  }
  throw new Error('Scheduler execution did not reach a fresh successful status within the bounded wait.');
}
main().catch(error=>{
  evidence.failure={status:error.response?.status??null,message:error.response?.data?.error?.message??error.message};
  fs.writeFileSync(path.join(root,'firebase-live-scheduler-smoke.json'),`${JSON.stringify(evidence,null,2)}\n`);
  process.stderr.write(`${JSON.stringify(evidence.failure)}\n`);
  process.exitCode=1;
});
