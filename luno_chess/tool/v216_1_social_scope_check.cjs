const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(path.join(root, file))).digest('hex');
const before = read('qa/v216_1/social-before/source/native_hubs_screen.dart.txt');
const current = read('lib/screens/native_hubs_screen.dart');
const owned = new Set([
  'FriendsScreen', '_FriendsScreenState', 'InboxScreen', '_InboxScreenState',
  'DirectMessageScreen', '_DirectMessageScreenState', 'EditProfileScreen',
  '_EditProfileScreenState', '_SocialViewport', '_FriendsVisualTabs',
  '_ProfileIdentityPreview', '_ProfileFieldHeading',
]);

function classes(source) {
  const starts = [...source.matchAll(/^class (\w+)\b/gm)];
  return new Map(starts.map((match, index) => [
    match[1], source.slice(match.index, starts[index + 1]?.index ?? source.length),
  ]));
}

const oldClasses = classes(before);
const newClasses = classes(current);
const checks = [];
const check = (name, pass) => checks.push({ name, pass });
check('imports and preamble unchanged', before.slice(0, before.indexOf('class ')) ===
  current.slice(0, current.indexOf('class ')));
for (const [name, source] of oldClasses) {
  if (!owned.has(name)) check(`protected class ${name}`, newClasses.get(name) === source);
}
for (const name of newClasses.keys()) {
  if (!oldClasses.has(name)) check(`new helper is social-owned: ${name}`, owned.has(name));
}
for (const name of [
  '_FriendsScreenState', '_InboxScreenState', '_DirectMessageScreenState',
  '_EditProfileScreenState',
]) {
  const prefix = source => source.slice(0, source.indexOf('  @override\n  Widget build('));
  check(`account, input and async logic unchanged: ${name}`,
    prefix(oldClasses.get(name)) === prefix(newClasses.get(name)));
}
const tail = (source, marker) => source.slice(source.indexOf(marker));
check('inbox conversation routing unchanged',
  tail(oldClasses.get('_InboxScreenState'), '  Widget _conversationTile(') ===
  tail(newClasses.get('_InboxScreenState'), '  Widget _conversationTile('));
const friendGuard = source => source.slice(source.indexOf('  void _openFriendProfile('),
  source.indexOf('  Widget _request('));
check('friend profile route and row validation unchanged',
  friendGuard(oldClasses.get('_FriendsScreenState')) ===
  friendGuard(newClasses.get('_FriendsScreenState')));

const deckBefore = read('qa/v216_1/social-before/source/battle_deck_screen.dart.txt');
const deckCurrent = read('lib/screens/battle_deck_screen.dart');
const oldStyle = '                                    color: LunoColors.ivory,\n';
const newStyle = [
  '                                    style: IconButton.styleFrom(',
  '                                      backgroundColor: const Color(0xFF07141A),',
  '                                      foregroundColor: LunoColors.ivory,',
  '                                      side: const BorderSide(color: LunoColors.gold),',
  '                                      minimumSize: const Size(48, 48),',
  '                                      padding: const EdgeInsets.all(10),',
  '                                    ),',
  '',
].join('\n');
const infoIndex = deckBefore.indexOf('                                      Icons.info_outline_rounded,');
const styleIndex = deckBefore.indexOf(oldStyle, infoIndex);
const expectedDeck = deckBefore.slice(0, styleIndex) + newStyle +
  deckBefore.slice(styleIndex + oldStyle.length);
check('battle deck changes are exactly info-icon style only', styleIndex >= 0 && expectedDeck === deckCurrent);

const report = {
  kind: 'static-scope-check-not-flutter-analysis',
  pass: checks.every(result => result.pass),
  checks,
  sha256: Object.fromEntries([
    'lib/screens/native_hubs_screen.dart', 'lib/screens/battle_deck_screen.dart',
    'test/v216_1_social_visual_test.dart',
  ].map(file => [file, hash(file)])),
  historicalV216: Object.fromEntries([
    'edit-profile-tr-390', 'friends-en-320', 'inbox-empty-tr-390',
    'dm-tr-390', 'deck-tr-320-text150',
  ].map(name => [`${name}-v216.png`, hash(`qa/v216_1/social-before/${name}-v216.png`)])),
};
fs.writeFileSync(path.join(root, 'qa/v216_1/social-scope-check.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
if (!report.pass) process.exitCode = 1;
