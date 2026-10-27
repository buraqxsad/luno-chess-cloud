'use strict';
const {readFileSync}=require('node:fs');
const {auditSettlements}=require('../lib/settlement-audit');

try{
  if(process.argv.length!==3)throw new Error('Usage: node scripts/audit-settlements.js <root-snapshot.json>');
  const root=JSON.parse(readFileSync(process.argv[2],'utf8'));
  process.stdout.write(JSON.stringify(auditSettlements(root),null,2)+'\n');
}catch(error){
  process.stderr.write('Settlement audit failed: '+error.message+'\n');
  process.exitCode=1;
}
