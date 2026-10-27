'use strict';
const fs = require('node:fs');
const path = require('node:path');
const qa = path.resolve(__dirname, '../qa');
const logs = {
  'source-audit-full-flutter.txt': ['v201b-full-flutter.txt'],
  'source-audit-analyze.txt': ['v201b-analyze.txt'],
  'source-audit-backend.txt': ['v201b-full-backend.txt'],
  'source-audit-typescript.txt': ['v201b-ts-contract.txt'],
  'source-audit-ts-typecheck.txt': ['v201b-ts-typecheck.txt'],
  'source-audit-emulator.txt': ['v201b-gate1-emulator.txt', 'v201b-gate5-emulator.txt'],
  'source-audit-dart-perft.txt': ['v201b-dart-perft.txt'],
  'source-audit-differential.txt': ['v201b-differential.txt'],
};
for (const [source, destinations] of Object.entries(logs)) {
  const file = path.join(qa, source), stat = fs.statSync(file);
  for (const destination of destinations) {
    const target = path.join(qa, destination);
    fs.copyFileSync(file, target);
    // Preserve run time: copying evidence must never manufacture freshness.
    fs.utimesSync(target, stat.atime, stat.mtime);
  }
}
console.log('Copied current run logs with their original modification times.');
