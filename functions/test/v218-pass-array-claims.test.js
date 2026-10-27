'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {syncPassState,passRewardVersion}=require('../lib/pass');
const {periodSnapshot}=require('../lib/economy');
const at=Date.UTC(2026,10,1),period=periodSnapshot(at);
function profile(claimed){return {passState:{seasonKey:'ranked-'+period.seasonId+'-v2',season:period.seasonNumber,level:4,xp:0,premium:true,claimed}};}
test('server preserves RTDB dense-array Pass claim markers during synchronization',()=>{
 const p=profile({free:[null,1000,2000,null,false],premium:[null,null,true]});
 const pass=syncPassState(p,at).pass;
 assert.deepEqual(pass.claimed.free,{'1':1000,'2':2000});assert.deepEqual(pass.claimed.premium,{'2':true});
 assert.deepEqual(syncPassState(p,at).pass.claimed,pass.claimed);
});
test('server claim normalization rejects malformed markers and out-of-track indices',()=>{
 const p=profile({free:{0:1,1:false,2:null,3:0,4:-1,5:1.5,6:Infinity,7:NaN,8:'1000','09':1000,30:1000,31:1000},premium:[]});
 assert.deepEqual(syncPassState(p,at).pass.claimed,{free:{30:1000},premium:{}});
});
test('unversioned earned premium array claims retain legacy rewards, false markers do not',()=>{
 const base={level:0,xp:0,premium:false};
 assert.equal(passRewardVersion({...base,claimed:{premium:[null,true]}},'s7'),1);
 assert.equal(passRewardVersion({...base,claimed:{premium:[null,false]}},'s7'),2);
 assert.equal(passRewardVersion({...base,claimed:{premium:{1:false}}},'s7'),2);
});
