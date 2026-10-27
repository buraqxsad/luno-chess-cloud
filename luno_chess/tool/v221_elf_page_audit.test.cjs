'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { auditElf64 } = require('./v221_elf_page_audit.cjs');
const root = path.resolve(__dirname, '..');

function fixture({ start = 0x4100, size = 0x300, relroStart = start, relroSize = size,
  align = 0x4000, sections = [{ addr: start, size, flags: 3 }], next } = {}) {
  const programs = [{ type: 1, flags: 6, offset: start % 0x4000, vaddr: start, filesz: size, memsz: size, align },
    ...(next ? [{ type: 1, flags: 6, offset: next.vaddr % 0x4000, filesz: next.size, memsz: next.size, align: 0x4000, ...next }] : []),
    { type: 0x6474e552, flags: 4, offset: relroStart % 0x4000, vaddr: relroStart, filesz: Math.min(size, relroSize), memsz: relroSize, align: 1 }];
  const buffer = Buffer.alloc(0x10000);
  Buffer.from([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]).copy(buffer);
  buffer.writeUInt16LE(3, 16);
  buffer.writeUInt16LE(183, 18);
  buffer.writeUInt32LE(1, 20);
  buffer.writeBigUInt64LE(64n, 32);
  buffer.writeBigUInt64LE(0xf000n, 40);
  buffer.writeUInt16LE(64, 52);
  buffer.writeUInt16LE(56, 54);
  buffer.writeUInt16LE(programs.length, 56);
  buffer.writeUInt16LE(64, 58);
  buffer.writeUInt16LE(sections.length + 1, 60);
  programs.forEach((p, i) => {
    const at = 64 + i * 56;
    buffer.writeUInt32LE(p.type, at);
    buffer.writeUInt32LE(p.flags, at + 4);
    [p.offset, p.vaddr, p.vaddr, p.filesz, p.memsz, p.align].forEach((v, j) => buffer.writeBigUInt64LE(BigInt(v), at + 8 + j * 8));
  });
  sections.forEach((s, i) => {
    const at = 0xf000 + (i + 1) * 64;
    buffer.writeUInt32LE(8, at + 4); // NOBITS keeps the fixture focused on memory geometry.
    buffer.writeBigUInt64LE(BigInt(s.flags ?? 3), at + 8);
    buffer.writeBigUInt64LE(BigInt(s.addr), at + 16);
    buffer.writeBigUInt64LE(BigInt(s.size), at + 32);
    buffer.writeBigUInt64LE(1n, at + 48);
  });
  return buffer;
}

const has = (report, code) => report.issues.some((issue) => issue.code === code);

test('whole LOAD and RELRO padding pass without requiring end modulo 16K', () => {
  for (const relroSize of [0x300, 0x1f00]) {
    const bytes = fixture({ relroSize, sections: [{ addr: 0x4100, size: 0x300 }, { addr: 0x4400, size: 0 }] });
    const snapshot = Buffer.from(bytes);
    const report = auditElf64(bytes);
    assert.equal(report.status, 'pass', JSON.stringify(report.issues));
    assert.equal(report.relroChecks[0].entireLoadSections, true);
    assert.equal(report.relroChecks[0].roundedEnd, '0x8000');
    assert.deepEqual(bytes, snapshot);
    assert.deepEqual(auditElf64(bytes), report);
    assert.doesNotThrow(() => JSON.stringify(report));
  }
});

test('non-entire LOAD uses AOSP aligned prefix and suffix rules', () => {
  const prefix = auditElf64(fixture({ size: 0x7f00, relroSize: 0x3f00,
    sections: [{ addr: 0x4100, size: 0x3f00 }, { addr: 0x8000, size: 0x4000 }] }));
  const suffix = auditElf64(fixture({ size: 0x4200, relroStart: 0x8000, relroSize: 0x300,
    sections: [{ addr: 0x4100, size: 0x3f00 }, { addr: 0x8000, size: 0x300 }] }));
  for (const report of [prefix, suffix]) {
    assert.equal(report.status, 'pass', JSON.stringify(report.issues));
    assert.equal(report.relroChecks[0].entireLoadSections, false);
    assert.equal(report.relroChecks[0].prefixValid, true);
    assert.equal(report.relroChecks[0].suffixValid, true);
  }
});

test('misaligned partial prefix with writable tail fails, even with sparse sections', () => {
  for (const sections of [[{ addr: 0x4100, size: 0x100 }, { addr: 0x4200, size: 0x200 }], []]) {
    const report = auditElf64(fixture({ relroSize: 0x100, sections }));
    assert.equal(report.status, 'fail');
    assert.ok(has(report, 'RELRO_WRITABLE_TAIL_OR_PREFIX'));
    if (sections.length) assert.ok(has(report, 'RELRO_SUFFIX'));
  }
});

test('misaligned partial suffix with writable prefix fails', () => {
  const report = auditElf64(fixture({ relroStart: 0x4200, relroSize: 0x200,
    sections: [{ addr: 0x4100, size: 0x100 }, { addr: 0x4200, size: 0x200 }] }));
  assert.ok(has(report, 'RELRO_PREFIX'));
  assert.ok(has(report, 'RELRO_WRITABLE_TAIL_OR_PREFIX'));
});

test('rounded RELRO cannot overlap an adjacent independent writable LOAD', () => {
  const report = auditElf64(fixture({ next: { vaddr: 0x7000, size: 0x100 } }));
  assert.equal(report.relroChecks[0].entireLoadSections, true);
  assert.ok(has(report, 'RELRO_WRITABLE_LOAD_COLLISION'));
  assert.deepEqual(report.relroChecks[0].independentWritableLoadCollisions, [1]);
  const rawOverlap = auditElf64(fixture({ relroSize: 0x3000, next: { vaddr: 0x7000, size: 0x100 } }));
  assert.ok(has(rawOverlap, 'RELRO_NEXT_LOAD'));
});

test('LOAD low alignment and offset/vaddr incongruence fail', () => {
  assert.ok(has(auditElf64(fixture({ align: 0x1000 })), 'LOAD_ALIGNMENT'));
  const bytes = fixture();
  bytes.writeBigUInt64LE(0x101n, 64 + 8);
  assert.ok(has(auditElf64(bytes), 'LOAD_CONGRUENCE'));
});

test('truncated, malformed, overflow and unsupported inputs fail closed', () => {
  const cases = [
    [Buffer.alloc(12), 'TRUNCATED'],
    [fixture().subarray(0, 0xf010), 'TRUNCATED'],
    [null, 'UNSUPPORTED_INPUT'],
  ];
  function changed(edit, code) { const bytes = fixture(); edit(bytes); cases.push([bytes, code]); }
  changed((b) => { b[0] = 0; }, 'MALFORMED_MAGIC');
  changed((b) => { b[4] = 1; }, 'UNSUPPORTED_FORMAT');
  changed((b) => { b[5] = 2; }, 'UNSUPPORTED_FORMAT');
  changed((b) => b.writeUInt16LE(40, 18), 'UNSUPPORTED_TARGET');
  changed((b) => b.writeUInt16LE(0, 60), 'UNSUPPORTED_TABLES');
  changed((b) => b.writeUInt16LE(0xffff, 56), 'UNSUPPORTED_TABLES');
  changed((b) => b.writeBigUInt64LE(0xfffffffffffffff0n, 64 + 16), 'MALFORMED_RANGE');
  changed((b) => b.writeBigUInt64LE(0x10000n, 64 + 8), 'TRUNCATED');
  changed((b) => b.writeBigUInt64LE(0x400n, 64 + 32), 'MALFORMED_SEGMENT');
  changed((b) => b.writeBigUInt64LE(0x6000n, 64 + 48), 'MALFORMED_ALIGNMENT');
  changed((b) => b.writeBigUInt64LE(0x9000n, 0xf040 + 16), 'MALFORMED_SECTION');
  changed((b) => b.writeUInt32LE(1, 0xf040), 'MALFORMED_STRINGS');
  for (const [bytes, code] of cases) {
    const report = auditElf64(bytes);
    assert.equal(report.status, 'fail');
    assert.ok(has(report, code), `${code}: ${JSON.stringify(report.issues)}`);
  }
});

const archived = [
  ['app-arm64-v8a-release/lib/arm64-v8a/libdatastore_shared_counter.so', 'arm64-v8a', '0x4000', '0x8000', [16, 17, 18, 19, 20]],
  ['app-arm64-v8a-release/lib/arm64-v8a/libflutter.so', 'arm64-v8a', '0xae4000', '0xb44000', [17, 18, 19, 20, 21, 22, 23]],
  ['app-x86_64-release/lib/x86_64/libdatastore_shared_counter.so', 'x86_64', '0x4000', '0x8000', [16, 17, 18, 19]],
];
for (const [relative, architecture, roundedStart, roundedEnd, indexes] of archived) {
  test(`actual archived ${relative}`, () => {
    const report = auditElf64(fs.readFileSync(path.join(root, 'qa/v220/artifacts', relative)));
    assert.equal(report.status, 'pass', JSON.stringify(report.issues));
    assert.equal(report.header.architecture, architecture);
    assert.ok(report.loadChecks.every((c) => c.alignment16k && c.congruent16k && c.congruentDeclaredAlignment));
    assert.equal(report.relroChecks.length, 1);
    const relro = report.relroChecks[0];
    assert.equal(relro.entireLoadSections, true);
    assert.deepEqual(relro.loadSectionIndexes, indexes);
    assert.deepEqual(relro.relroSectionIndexes, indexes);
    assert.equal(relro.roundedStart, roundedStart);
    assert.equal(relro.roundedEnd, roundedEnd);
    assert.deepEqual(relro.independentWritableLoadCollisions, []);
  });
}

test('CLI emits JSON, audits all supplied paths, and rejects usage/read failures', () => {
  const script = path.join(__dirname, 'v221_elf_page_audit.cjs');
  const paths = archived.map(([relative]) => path.join(root, 'qa/v220/artifacts', relative));
  const run = (args) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', timeout: 5000, maxBuffer: 1024 * 1024 });
  const good = run(paths);
  assert.equal(good.status, 0, good.stderr);
  assert.equal(good.stderr, '');
  assert.equal(JSON.parse(good.stdout).results.length, 3);
  const mixed = run([paths[0], path.join(root, 'qa/v221/android/absent.so')]);
  assert.equal(mixed.status, 1);
  assert.deepEqual(JSON.parse(mixed.stdout).results.map((r) => r.status), ['pass', 'fail']);
  const empty = run([]);
  assert.equal(empty.status, 1);
  assert.equal(JSON.parse(empty.stdout).issues[0].code, 'USAGE');
});
