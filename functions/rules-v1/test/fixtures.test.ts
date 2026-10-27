import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {runFixture,type Fixture} from './fixture_support.js';
const fixtures=JSON.parse(readFileSync(resolve(__dirname,'../../../../battle_contract/v1/rules.json'),'utf8')).fixtures as Fixture[];
for(const fixture of fixtures)test(fixture.fixtureId+' — '+fixture.intent,()=>{runFixture(fixture);});
