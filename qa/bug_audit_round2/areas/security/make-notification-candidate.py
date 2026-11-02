from pathlib import Path
import hashlib,json,subprocess,difflib
repo=Path('/workspace/luno-chess');out=Path('/workspace/luno-review/bug-audit-round2/security');p=repo/'functions/index.js';source=p.read_text()
helper="""async function rateLimitAccountDeletion(uid){
  const deletion=(await db.ref(`accountDeletions/${hash(uid)}`).get()).val();
  if(!deletion||deletion.status!=='processing')return rateLimit(uid,'deleteAccount',3,60*60*1000);
  // The owner may need more than three bounded cleanup pages/attempts. Keep
  // resume traffic bounded without charging it against first-entry attempts.
  const ref=db.ref(`serverRateLimits/${uid}/deleteAccountResume/${Math.floor(now()/60000)}`);
  const result=await writeAccountMetadata(uid,'deleteAccount',()=>ref.transaction(function(value){
    const count=safeInt(value,0);return count>=30?undefined:count+1;
  },undefined,false),()=>ref.remove());
  if(!result.committed)throw httpError(429,'rate-limited','Too many account deletion retries.');
}
async function eraseAuthoredNotifications(uid,deletionRef){
  const progress=(await deletionRef.get()).val()||{};
  if(progress.notificationsErased===true)return;
  const root=db.ref('notifications'),pageSize=5,pageBudget=40,deadline=now()+15000;
  let cursor=typeof progress.notificationCursor==='string'?progress.notificationCursor:null;
  const finish=()=>deletionRef.update({notificationCursor:null,notificationsErased:true});
  for(let pageNumber=0;pageNumber<pageBudget;pageNumber++){
    let query=root.orderByKey();if(cursor!==null)query=query.startAfter(cursor);
    const page=await query.limitToFirst(pageSize).get(),recipients=[];
    // RTDB integer-key order is not JavaScript lexicographic order.
    page.forEach(child=>{recipients.push(child);return false;});
    if(!recipients.length){await finish();return;}
    for(const recipient of recipients){
      const notices=recipient.val()||{};
      for(const [key,notice] of Object.entries(notices)){
        if(!notice||notice.fromUid!==uid)continue;
        if(now()>=deadline)throw httpError(503,'account-deletion-in-progress','Notification cleanup is still in progress. Retry account deletion.');
        await root.child(recipient.key).child(key).transaction(function(value){
          if(value===null)return null;
          return value.fromUid===uid?null:undefined;
        },undefined,false);
      }
    }
    // Advance only after every owned notice in the page was removed. Failures
    // retain the prior checkpoint, so retries cannot skip unfinished data.
    cursor=recipients.at(-1).key;
    await deletionRef.update({notificationCursor:cursor});
    if(recipients.length<pageSize){await finish();return;}
    if(now()>=deadline)throw httpError(503,'account-deletion-in-progress','Notification cleanup is still in progress. Retry account deletion.');
  }
  if(!(await root.orderByKey().startAfter(cursor).limitToFirst(1).get()).exists()){await finish();return;}
  throw httpError(503,'account-deletion-in-progress','Notification cleanup is still in progress. Retry account deletion.');
}
"""
needle='async function deleteAccount(context){';assert source.count(needle)==1
candidate=source.replace(needle,helper+needle)
needle2="    await deletionRef.update({status:'processing',requestIdHash:hash(context.requestId),updatedAt:ServerValue.TIMESTAMP});"
assert candidate.count(needle2)==1
candidate=candidate.replace("  await rateLimit(uid,'deleteAccount',3,60*60*1000);","  await rateLimitAccountDeletion(uid);")
candidate=candidate.replace(needle2,needle2+"\n    // Rejected/expired relationships can lose every recipient edge. Scan small\n    // recipient pages to erase their pushed notices too, before deletion can finish.\n    await eraseAuthoredNotifications(uid,deletionRef);")
(out/'notification-erasure.patch').write_text(''.join(difflib.unified_diff(source.splitlines(True),candidate.splitlines(True),fromfile='a/functions/index.js',tofile='b/functions/index.js')))
(out/'notification-candidate-index.cjs').write_text(candidate)
(out/'notification-candidate-preload.cjs').write_text("const {Module}=require('node:module');const fs=require('node:fs');const path=require('node:path');const original='/workspace/luno-chess/functions/index.js';const m=new Module(original,module);m.filename=original;m.paths=Module._nodeModulePaths(path.dirname(original));m._compile(fs.readFileSync('/workspace/luno-review/bug-audit-round2/security/notification-candidate-index.cjs','utf8'),original);require.cache[original]=m;\n")
(out/'notification-candidate-provenance.json').write_text(json.dumps({'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'candidate_sha256':hashlib.sha256(candidate.encode()).hexdigest(),'changes':['bounded checkpointed notification erasure helper','call after processing marker, before any completed deletion'],'repo_source_modified':False},indent=2)+'\n')
print('Candidate and minimal patch prepared; repository production source untouched.')
