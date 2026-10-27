const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex');
const socialSource = 'qa/v216_1/social-before/source/native_hubs_screen.dart.txt';
const deckSource = 'qa/v216_1/social-before/source/battle_deck_screen.dart.txt';
const names = new Map([
  ['FriendsScreen', 'V216BeforeFriendsScreen'],
  ['_FriendsScreenState', '_V216BeforeFriendsScreenState'],
  ['InboxScreen', 'V216BeforeInboxScreen'],
  ['_InboxScreenState', '_V216BeforeInboxScreenState'],
  ['DirectMessageScreen', 'V216BeforeDirectMessageScreen'],
  ['_DirectMessageScreenState', '_V216BeforeDirectMessageScreenState'],
  ['EditProfileScreen', 'V216BeforeEditProfileScreen'],
  ['_EditProfileScreenState', '_V216BeforeEditProfileScreenState'],
  ['BattleSelectedDeckGrid', 'V216BeforeBattleSelectedDeckGrid'],
]);

function classes(source) {
  const starts = [...source.matchAll(/^class (\w+)\b/gm)];
  return new Map(starts.map((match, index) => [
    match[1], source.slice(match.index, starts[index + 1]?.index ?? source.length),
  ]));
}

function rename(source) {
  return source.replace(/\b\w+\b/g, word => names.get(word) ?? word);
}

function imports(source) {
  return source.split('\n').filter(line => line.startsWith('import ')).map(line =>
    line.replace(/'\.\.\/(.*?)'/, "'package:luno_chess/$1'")
      .replace(/'([\w_]+\.dart)'/, "'package:luno_chess/screens/$1'"));
}

function fixture(sourceFile, owned, extraImport) {
  const source = read(sourceFile);
  const blocks = classes(source);
  return [
    '// Frozen pre-social-edit owned classes. Do not mirror production fixes.',
    `// Source: ${sourceFile}`,
    `// Raw source SHA-256: ${hash(sourceFile)}`,
    '// Only class identifiers and import paths are adapted; shared dependencies remain current.',
    '// ignore_for_file: unused_import',
    ...imports(source),
    extraImport,
    '',
    ...[...blocks].filter(([name]) => owned.has(name)).map(([, block]) => rename(block)),
  ].join('\n').trimEnd() + '\n';
}

const fixtures = new Map([
  ['test/helpers/v216_1_social_before.dart', fixture(socialSource, new Set([
    ...[...names.keys()].filter(name => name !== 'BattleSelectedDeckGrid'),
    '_InboxBadge', '_Tabs',
  ]), "import 'package:luno_chess/screens/native_hubs_screen.dart';")],
  ['test/helpers/v216_1_social_deck_before.dart', fixture(deckSource,
    new Set(['BattleSelectedDeckGrid']),
    "import 'package:luno_chess/screens/battle_deck_screen.dart' show showBattleCatalogDetail;")],
]);

if (process.argv.includes('--patch')) {
  console.log('*** Begin Patch\n' + [...fixtures].map(([file, source]) =>
    `*** Add File: ${file}\n` + source.trimEnd().split('\n').map(line => '+' + line).join('\n')
  ).join('\n') + '\n*** End Patch');
} else {
  const checks = [...fixtures].map(([file, expected]) => ({
    file,
    exactAdaptedCopy: fs.existsSync(path.join(root, file)) && read(file) === expected,
  }));
  const pass = checks.every(check => check.exactAdaptedCopy);
  console.log(JSON.stringify({
    kind: 'read-only-frozen-source-provenance-check', pass, checks,
    sourceSha256: { [socialSource]: hash(socialSource), [deckSource]: hash(deckSource) },
  }, null, 2));
  if (!pass) process.exitCode = 1;
}
