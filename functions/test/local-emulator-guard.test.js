'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const path=require('node:path');
const {requireLocalEmulators}=require('./helpers/local-emulators');
const local={FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099',FIREBASE_DATABASE_EMULATOR_HOST:'localhost:9000'};

test('integration environment accepts explicit loopback endpoints',()=>{
  assert.deepEqual(requireLocalEmulators(local),{authHost:'127.0.0.1:9099',databaseHost:'localhost:9000',functionsBase:''});
  const functionsBase='http://127.0.0.1:5001/luno-chess/europe-west1/api';
  assert.equal(requireLocalEmulators({...local,LUNO_FUNCTIONS_BASE_URL:functionsBase}).functionsBase,functionsBase);
});

for(const key of Object.keys(local)){
  for(const value of [undefined,'','0.0.0.0:9000','example.com:9000','localhost:0','localhost:65536','http://localhost:9000','localhost:9000/path']){
    test(`${key} rejects ${String(value)}`,()=>{
      assert.throws(()=>requireLocalEmulators({...local,[key]:value}),/local emulator/);
    });
  }
}
for(const value of ['https://example.com/api','http://0.0.0.0:5001','http://localhost:0','http://user:secret@localhost:5001','http://localhost:5001?target=remote','http://localhost:5001#fragment','invalid']){
  test(`Functions endpoint rejects ${value}`,()=>{
    assert.throws(()=>requireLocalEmulators({...local,LUNO_FUNCTIONS_BASE_URL:value}),/local Functions emulator/);
  });
}
for(const file of ['dm','friends','online','shop','pass','legal-consent','emulator','player-state','account-metadata','pass-chest-recovery','shop-chest-recovery','soft-purchase-recovery','pass-purchase-recovery','retained-data-erasure','retained-record-race']){
  test(`${file} integration refuses to start without explicit emulator configuration`,()=>{
    const env={...process.env};
    delete env.FIREBASE_AUTH_EMULATOR_HOST;
    delete env.FIREBASE_DATABASE_EMULATOR_HOST;
    delete env.LUNO_FUNCTIONS_BASE_URL;
    const result=spawnSync(process.execPath,[path.join(__dirname,file+'.integration.js')],{env,encoding:'utf8',timeout:10000});
    assert.equal(result.error,undefined);
    assert.notEqual(result.status,0);
    assert.match(result.stderr,/FIREBASE_AUTH_EMULATOR_HOST must explicitly target a local emulator/);
  });
}
