'use strict';

const PAGE = 16384n;
const MAX_U64 = (1n << 64n) - 1n;
const PT_LOAD = 1;
const PT_GNU_RELRO = 0x6474e552;
const PF_W = 2;
const RULE_SOURCE = 'https://android.googlesource.com/platform/tools/base/+/7765a1e4385997e1919311925a88cbd12218f818/sdk-common/src/main/java/com/android/ide/common/pagealign/PageAlignUtils.kt';
const hex = (value) => `0x${value.toString(16)}`;
const overlap = (a, b, c, d) => a < b && c < d && a < d && c < b;
const powerOfTwo = (value) => value > 0n && (value & (value - 1n)) === 0n;

class ElfError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function requireElf(condition, code, message) {
  if (!condition) throw new ElfError(code, message);
}

function endOf(start, size, label) {
  const end = start + size;
  requireElf(end <= MAX_U64, 'MALFORMED_RANGE', `${label} overflows uint64`);
  return end;
}

function parseElf64(bytes) {
  requireElf(Buffer.isBuffer(bytes), 'UNSUPPORTED_INPUT', 'Expected a Buffer');
  requireElf(bytes.length >= 64, 'TRUNCATED', 'ELF64 header is incomplete');
  requireElf(bytes.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46])), 'MALFORMED_MAGIC', 'Not an ELF file');
  requireElf(bytes[4] === 2 && bytes[5] === 1, 'UNSUPPORTED_FORMAT', 'Only little-endian ELF64 is supported');
  requireElf(bytes[6] === 1 && bytes.readUInt32LE(20) === 1, 'UNSUPPORTED_VERSION', 'Expected ELF version 1');
  const type = bytes.readUInt16LE(16);
  const machine = bytes.readUInt16LE(18);
  requireElf(type === 3 && (machine === 183 || machine === 62), 'UNSUPPORTED_TARGET', 'Expected Android AArch64 or x86_64 ET_DYN');
  requireElf(bytes.readUInt16LE(52) === 64, 'MALFORMED_HEADER', 'Expected 64-byte ELF header');
  const phoff = bytes.readBigUInt64LE(32);
  const shoff = bytes.readBigUInt64LE(40);
  const phentsize = bytes.readUInt16LE(54);
  const phnum = bytes.readUInt16LE(56);
  const shentsize = bytes.readUInt16LE(58);
  const shnum = bytes.readUInt16LE(60);
  const shstrndx = bytes.readUInt16LE(62);
  requireElf(phnum > 0 && phnum !== 0xffff && shnum > 0 && shstrndx !== 0xffff,
    'UNSUPPORTED_TABLES', 'Missing or extended-count header tables are unsupported');
  requireElf(phentsize === 56 && shentsize === 64, 'UNSUPPORTED_TABLES', 'Expected standard ELF64 entry sizes');
  requireElf(phoff >= 64n && shoff >= 64n, 'MALFORMED_TABLES', 'Header tables overlap the ELF header');
  function fileRange(offset, size, label) {
    const end = endOf(offset, size, label);
    requireElf(end <= BigInt(bytes.length), 'TRUNCATED', `${label} extends beyond file`);
    return Number(offset);
  }
  const phend = endOf(phoff, BigInt(phentsize * phnum), 'Program header table');
  const shend = endOf(shoff, BigInt(shentsize * shnum), 'Section header table');
  fileRange(phoff, BigInt(phentsize * phnum), 'Program header table');
  fileRange(shoff, BigInt(shentsize * shnum), 'Section header table');
  requireElf(!overlap(phoff, phend, shoff, shend), 'MALFORMED_TABLES', 'Header tables overlap');
  const programs = [];
  for (let index = 0; index < phnum; index++) {
    const at = Number(phoff) + index * phentsize;
    const p = {
      index, type: bytes.readUInt32LE(at), flags: bytes.readUInt32LE(at + 4),
      offset: bytes.readBigUInt64LE(at + 8), vaddr: bytes.readBigUInt64LE(at + 16),
      paddr: bytes.readBigUInt64LE(at + 24), filesz: bytes.readBigUInt64LE(at + 32),
      memsz: bytes.readBigUInt64LE(at + 40), align: bytes.readBigUInt64LE(at + 48),
    };
    p.end = endOf(p.vaddr, p.memsz, `Program ${index}`);
    fileRange(p.offset, p.filesz, `Program ${index} file contents`);
    if (p.type === PT_LOAD || p.type === PT_GNU_RELRO) {
      requireElf(p.filesz <= p.memsz, 'MALFORMED_SEGMENT', `Program ${index} filesz exceeds memsz`);
    }
    if (p.type === PT_LOAD) {
      requireElf(p.align <= 1n || powerOfTwo(p.align), 'MALFORMED_ALIGNMENT', `LOAD ${index} alignment is not a power of two`);
    }
    programs.push(p);
  }
  const sections = [];
  for (let index = 0; index < shnum; index++) {
    const at = Number(shoff) + index * shentsize;
    const s = {
      index, nameOffset: bytes.readUInt32LE(at), type: bytes.readUInt32LE(at + 4),
      flags: bytes.readBigUInt64LE(at + 8), addr: bytes.readBigUInt64LE(at + 16),
      offset: bytes.readBigUInt64LE(at + 24), size: bytes.readBigUInt64LE(at + 32),
      link: bytes.readUInt32LE(at + 40), info: bytes.readUInt32LE(at + 44),
      addralign: bytes.readBigUInt64LE(at + 48), entsize: bytes.readBigUInt64LE(at + 56),
    };
    s.end = endOf(s.addr, s.size, `Section ${index}`);
    if (s.type !== 0 && s.type !== 8) fileRange(s.offset, s.size, `Section ${index} file contents`);
    requireElf(s.addralign <= 1n || powerOfTwo(s.addralign), 'MALFORMED_ALIGNMENT', `Section ${index} alignment is not a power of two`);
    requireElf(s.link < shnum, 'MALFORMED_SECTION', `Section ${index} link is out of range`);
    requireElf(s.entsize === 0n || s.size % s.entsize === 0n, 'MALFORMED_SECTION', `Section ${index} has a partial entry`);
    sections.push(s);
  }
  requireElf(sections[0].type === 0, 'MALFORMED_SECTION', 'Section zero must be SHT_NULL');
  requireElf(shstrndx < shnum, 'MALFORMED_STRINGS', 'Section name table index is out of range');
  if (shstrndx === 0) {
    requireElf(sections.every((s) => s.nameOffset === 0), 'MALFORMED_STRINGS', 'Names exist without a section name table');
    sections.forEach((s) => { s.name = null; });
  } else {
    const strings = sections[shstrndx];
    requireElf(strings.type === 3 && strings.size > 0n, 'MALFORMED_STRINGS', 'Expected a nonempty SHT_STRTAB');
    const names = bytes.subarray(Number(strings.offset), Number(strings.offset + strings.size));
    requireElf(names[0] === 0 && names[names.length - 1] === 0, 'MALFORMED_STRINGS', 'String table must start and end with NUL');
    for (const s of sections) {
      requireElf(s.nameOffset < names.length, 'MALFORMED_STRINGS', `Section ${s.index} name is out of range`);
      s.name = names.toString('utf8', s.nameOffset, names.indexOf(0, s.nameOffset));
    }
  }
  const loads = programs.filter((p) => p.type === PT_LOAD).sort((a, b) => a.vaddr < b.vaddr ? -1 : a.vaddr > b.vaddr ? 1 : a.index - b.index);
  requireElf(loads.some((p) => p.memsz > 0n), 'MALFORMED_LOADS', 'No nonempty PT_LOAD');
  for (let i = 1; i < loads.length; i++) {
    requireElf(!overlap(loads[i - 1].vaddr, loads[i - 1].end, loads[i].vaddr, loads[i].end),
      'UNSUPPORTED_LOAD_OVERLAP', 'Overlapping live LOAD ranges are unsupported');
  }
  for (const s of sections.filter((s) => (s.flags & 2n) !== 0n)) {
    requireElf(loads.some((p) => s.addr >= p.vaddr && s.end <= p.end),
      'MALFORMED_SECTION', `Allocated section ${s.index} is outside every LOAD`);
  }
  return { header: { type, machine, architecture: machine === 183 ? 'arm64-v8a' : 'x86_64',
    entry: bytes.readBigUInt64LE(24), phoff, shoff, phentsize, phnum, shentsize, shnum, shstrndx }, programs, sections, loads };
}

function jsonFields(record) {
  return Object.fromEntries(Object.entries(record).map(([key, value]) => [key, typeof value === 'bigint' ? hex(value) : value]));
}

// Pure Buffer -> JSON-safe report. No filesystem, hash, environment or filename decisions.
function auditElf64(bytes) {
  const report = { schemaVersion: 1, pageSize: Number(PAGE), ruleSource: RULE_SOURCE,
    status: 'fail', header: null, programHeaders: [], sectionHeaders: [], loadChecks: [], relroChecks: [], issues: [] };
  const issue = (code, message, fields = {}) => report.issues.push({ code, message, ...fields });
  let elf;
  try {
    elf = parseElf64(bytes);
  } catch (error) {
    if (!(error instanceof ElfError)) throw error;
    issue(error.code, error.message);
    return report;
  }
  report.header = jsonFields(elf.header);
  report.programHeaders = elf.programs.map(jsonFields);
  report.sectionHeaders = elf.sections.map(jsonFields);
  for (const p of elf.loads) {
    const check = { programIndex: p.index, alignment16k: p.align >= PAGE,
      congruent16k: p.offset % PAGE === p.vaddr % PAGE,
      congruentDeclaredAlignment: p.align <= 1n || p.offset % p.align === p.vaddr % p.align };
    report.loadChecks.push(check);
    if (!check.alignment16k) issue('LOAD_ALIGNMENT', 'LOAD p_align is below 16384', { programIndex: p.index });
    if (!check.congruent16k || !check.congruentDeclaredAlignment) issue('LOAD_CONGRUENCE', 'LOAD offset and vaddr are not congruent', { programIndex: p.index });
  }
  function contained(segment) {
    // AOSP compares (address,size) lists, including nonallocated and zero-size sections.
    return elf.sections.filter((s) => s.addr >= segment.vaddr && s.end <= segment.end)
      .sort((a, b) => a.addr < b.addr ? -1 : a.addr > b.addr ? 1 : a.index - b.index);
  }
  for (const relro of elf.programs.filter((p) => p.type === PT_GNU_RELRO)) {
    const before = report.issues.length;
    const loadIndex = elf.loads.findLastIndex((p) => p.vaddr <= relro.vaddr);
    const load = elf.loads[loadIndex];
    const roundedStart = relro.vaddr - relro.vaddr % PAGE;
    const roundedEnd = (relro.end + PAGE - 1n) / PAGE * PAGE;
    const check = { programIndex: relro.index, containingLoadIndex: load?.index ?? null,
      roundedStart: hex(roundedStart), roundedEnd: hex(roundedEnd), entireLoadSections: false,
      loadSectionIndexes: [], relroSectionIndexes: [], prefixValid: false, suffixValid: false,
      independentWritableLoadCollisions: [], status: 'fail' };
    report.relroChecks.push(check);
    if (!load || relro.memsz === 0n || relro.vaddr >= load.end) {
      issue('RELRO_CONTAINMENT', 'Nonempty RELRO must start inside a LOAD', { programIndex: relro.index });
      continue;
    }
    if (roundedEnd > MAX_U64) issue('MALFORMED_RANGE', 'Rounded RELRO overflows uint64', { programIndex: relro.index });
    const next = elf.loads[loadIndex + 1];
    if (next && relro.end > next.vaddr) issue('RELRO_NEXT_LOAD', 'RELRO extends into the next LOAD', { programIndex: relro.index });
    const loadSections = contained(load);
    const relroSections = contained(relro);
    check.loadSectionIndexes = loadSections.map((s) => s.index);
    check.relroSectionIndexes = relroSections.map((s) => s.index);
    check.entireLoadSections = loadSections.length === relroSections.length &&
      loadSections.every((s, i) => s.addr === relroSections[i].addr && s.size === relroSections[i].size);
    check.prefixValid = relro.vaddr % PAGE === 0n || relro.vaddr === load.vaddr;
    check.suffixValid = relro.end % PAGE === 0n || relro.end === load.end;
    if (!check.entireLoadSections) {
      if (!check.prefixValid) issue('RELRO_PREFIX', 'RELRO start is neither page-aligned nor LOAD start', { programIndex: relro.index });
      if (!check.suffixValid) issue('RELRO_SUFFIX', 'RELRO end is neither page-aligned nor LOAD end', { programIndex: relro.index });
    }
    // Extra conservative safety gate: section identity never bypasses live writable bytes.
    if ((load.flags & PF_W) !== 0 &&
      (overlap(roundedStart, relro.vaddr, load.vaddr, load.end) || overlap(relro.end, roundedEnd, load.vaddr, load.end))) {
      issue('RELRO_WRITABLE_TAIL_OR_PREFIX', 'Rounded protection captures writable bytes outside RELRO in its LOAD', { programIndex: relro.index });
    }
    for (const other of elf.loads) {
      if (other.index !== load.index && (other.flags & PF_W) !== 0 && overlap(roundedStart, roundedEnd, other.vaddr, other.end)) {
        check.independentWritableLoadCollisions.push(other.index);
        issue('RELRO_WRITABLE_LOAD_COLLISION', 'Rounded protection captures an independent writable LOAD',
          { programIndex: relro.index, loadIndex: other.index });
      }
    }
    check.status = report.issues.length === before ? 'pass' : 'fail';
  }
  report.status = report.issues.length === 0 ? 'pass' : 'fail';
  return report;
}

module.exports = { auditElf64, RULE_SOURCE };

if (require.main === module) {
  const fs = require('node:fs');
  const paths = process.argv.slice(2);
  const output = { schemaVersion: 1, pageSize: Number(PAGE), status: 'fail', results: [] };
  if (paths.length === 0) {
    output.issues = [{ code: 'USAGE', message: 'Usage: node tool/v221_elf_page_audit.cjs <library.so> [...]' }];
  }
  for (const path of paths) {
    try {
      requireElf(path.toLowerCase().endsWith('.so'), 'UNSUPPORTED_PATH', 'Expected a .so path');
      output.results.push({ path, ...auditElf64(fs.readFileSync(path)) });
    } catch (error) {
      if (!(error instanceof ElfError) && !error.code) throw error;
      output.results.push({ path, status: 'fail', issues: [{ code: error.code, message: error.message }] });
    }
  }
  if (paths.length > 0 && output.results.every((result) => result.status === 'pass')) output.status = 'pass';
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  process.exitCode = output.status === 'pass' ? 0 : 1;
}
