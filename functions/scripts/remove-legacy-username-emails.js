'use strict';

const crypto=require('node:crypto');
const {applicationDefault,deleteApp,initializeApp}=require('firebase-admin/app');
const {getDatabase,ServerValue}=require('firebase-admin/database');

const apply=process.argv.includes('--apply');
const databaseURL=String(process.env.FIREBASE_DATABASE_URL||'').trim();

function fail(message){throw new Error(message);}
function digest(value){return crypto.createHash('sha256').update(String(value)).digest('hex');}

async function main(){
  if(!databaseURL)fail('FIREBASE_DATABASE_URL is required.');
  const app=initializeApp({credential:applicationDefault(),databaseURL},'username-email-migration');
  try{
    const db=getDatabase(app),snapshot=await db.ref('usernameEmails').get();
    const records=snapshot.val()||{},recordCount=Object.keys(records).length;
    const evidence={
      mode:apply?'apply':'dry-run',
      legacyRecordCount:recordCount,
      contentLogged:false,
      keysetDigest:digest(Object.keys(records).sort().join('\n')),
      databaseHost:new URL(databaseURL).host
    };
    console.log(JSON.stringify(evidence,null,2));
    if(!apply)return;
    if(process.env.LUNO_CONFIRM_LEGACY_USERNAME_EMAILS_DELETE!=='DELETE_LEGACY_USERNAME_EMAILS'){
      fail('Apply requires LUNO_CONFIRM_LEGACY_USERNAME_EMAILS_DELETE=DELETE_LEGACY_USERNAME_EMAILS.');
    }
    const backupReference=String(process.env.LUNO_USERNAME_EMAILS_BACKUP_REFERENCE||'').trim();
    if(!backupReference)fail('Apply requires LUNO_USERNAME_EMAILS_BACKUP_REFERENCE.');
    await db.ref().update({
      usernameEmails:null,
      'migrationState/usernameEmailsRemoval':{
        status:'complete',recordCount,keysetDigest:evidence.keysetDigest,
        backupReferenceHash:digest(backupReference),completedAt:ServerValue.TIMESTAMP
      }
    });
    if((await db.ref('usernameEmails').get()).exists())fail('Post-delete verification failed.');
    console.log(JSON.stringify({result:'complete',legacyRecordCount:recordCount,postDeleteExists:false},null,2));
  }finally{
    await deleteApp(app).catch(function(){});
  }
}

main().catch(function(error){console.error(String(error&&error.message||error));process.exit(1);});
