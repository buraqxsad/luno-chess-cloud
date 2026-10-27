'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const {auditSettlements}=require('../lib/settlement-audit');
const id='rm_'+'a'.repeat(32);
function fixture(){
  const result={winner:'W',type:'resign',finishedAt:123};
  const match={matchId:id,status:'finished',mode:'ranked',settlementStatus:'complete',result,
    players:{W:{uid:'w'},B:{uid:'b'}},participants:{w:true,b:true},colors:{w:'W',b:'B'}};
  const root={rankedState:{matches:{[id]:match}},users:{},matchHistory:{},rankedReplays:{},rankedMatchViews:{}};
  for(const uid of ['w','b']){
    const key=createHash('sha256').update(uid+'|'+id).digest('hex').slice(0,48);
    root.users[uid]={serverProgress:{rankedSettlements:{[key]:{matchId:id,outcome:uid==='w'?'win':'loss'}}}};
    for(const branch of ['matchHistory','rankedReplays','rankedMatchViews'])root[branch][uid]={[id]:{matchId:id,status:'finished',result:{...result}}};
  }
  return root;
}
test('consistent snapshot is inspected without mutation or private content output',()=>{
  const root=fixture();root.users.w.email='private@example.test';const before=JSON.stringify(root);
  const report=auditSettlements(root);
  assert.equal(report.findings[0].classification,'consistent-in-snapshot');
  assert.equal(report.automaticRepairAllowed,false);
  assert.equal(JSON.stringify(root),before);
  assert.ok(!JSON.stringify(report).includes('private@example.test'));
});
for(const branch of ['matchHistory','rankedReplays','rankedMatchViews'])test(`detects missing ${branch} despite complete marker`,()=>{
  const root=fixture();delete root[branch].w[id];
  assert.equal(auditSettlements(root).findings[0].classification,'publication-review');
});
test('missing reward ledger requires manual review, never automatic re-award',()=>{
  const root=fixture();root.users.w.serverProgress.rankedSettlements={};
  assert.ok(auditSettlements(root).findings[0].blockers.includes('W:missing-reward-ledger'));
});
test('missing profile and participant mismatch block repair',()=>{
  const root=fixture();delete root.users.b;root.rankedState.matches[id].colors.w='B';
  const report=auditSettlements(root).findings[0];
  assert.ok(report.blockers.includes('B:missing-profile'));
  assert.ok(report.blockers.includes('W:participant-mismatch'));
});
test('conflicting ledger outcome and stale result view are detected',()=>{
  const root=fixture();Object.values(root.users.w.serverProgress.rankedSettlements)[0].outcome='loss';
  root.rankedMatchViews.b[id].status='active';
  const finding=auditSettlements(root).findings[0];
  assert.ok(finding.blockers.includes('W:reward-ledger-mismatch'));
  assert.ok(finding.issues.includes('B:view'));
});
test('friendly matches do not require ranked reward ledgers',()=>{
  const root=fixture();root.rankedState.matches[id].mode='friendly';
  for(const uid of ['w','b'])root.users[uid].serverProgress.rankedSettlements={};
  assert.equal(auditSettlements(root).findings[0].classification,'consistent-in-snapshot');
});
test('new match presence is preserved conceptually; old active pointer is flagged',()=>{
  const root=fixture();root.rankedPlayers={w:{matchId:'new-match',status:'active'}};
  assert.deepEqual(auditSettlements(root).findings[0].issues,[]);
  root.rankedState.activeByUser={w:id};
  assert.ok(auditSettlements(root).findings[0].issues.includes('W:active-pointer'));
});
test('rejects partial root snapshot and skips active matches',()=>{
  assert.throws(()=>auditSettlements({}),/root snapshot/);
  const root=fixture();root.rankedState.matches[id].result=null;
  assert.equal(auditSettlements(root).checked,0);
});
