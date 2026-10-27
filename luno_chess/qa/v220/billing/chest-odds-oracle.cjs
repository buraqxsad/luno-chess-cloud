'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../../../..');
const catalogs = require(path.join(root, 'functions/lib/catalogs'));
const source = fs.readFileSync(path.join(root, 'functions/lib/chests.js'), 'utf8').replace(/\r\n/g, '\n');
const chance = (name) => vm.runInNewContext('(' + source.match(new RegExp('const ' + name + '=(\\{[^;]+?\\})\\[chestId\\]'))[1] + ')');
const pools = {skin: catalogs.SKIN_DROP_CATALOG, emoji: catalogs.EMOJI_DROP_CATALOG,
  frame_shard: catalogs.FRAME_SHARD_CATALOG, bioframe_shard: catalogs.BIO_FRAME_SHARD_CATALOG};
const fields = {skin: ['ownedSkins', 'skinPieces'], emoji: ['ownedEmojis', 'emojiPieces'],
  frame_shard: ['ownedFrames', 'frameShards'], bioframe_shard: ['ownedBioFrames', 'bioFrameShards']};
const gate = (p) => Math.ceil(p * 2 ** 32) / 2 ** 32;
const pick = (i, n) => (Math.ceil((i + 1) * 2 ** 32 / n) - Math.ceil(i * 2 ** 32 / n)) / 2 ** 32;

function inventory(only) {
  const result = {};
  for (const [kind, [owned, pieces]] of Object.entries(fields)) {
    result[owned] = only ? Object.keys(pools[kind]).filter(id => only !== kind + ':' + id) : [];
    result[pieces] = {};
  }
  return result;
}
function project(chestId, inv) {
  const chest = catalogs.CHEST_CATALOG[chestId], targets = [], groups = [];
  const missing = (kind, rarities) => Object.keys(pools[kind]).filter(id =>
    rarities.includes(pools[kind][id].rarity) && !inv[fields[kind][0]].includes(id) &&
    ((inv[fields[kind][1]] || {})[id] || 0) < pools[kind][id].target);
  for (const [key, drop] of Object.entries(chest.drops)) {
    if (key === 'gold' || drop.chance <= 0) continue;
    const [kind, rarity] = key.split('_'), ids = missing(kind, [rarity]);
    groups.push({kind, ids, chance: ids.length ? gate(drop.chance) : 0});
    ids.forEach(id => targets.push({kind, id, rarity, min: drop.min, max: drop.max}));
  }
  const rarities = ['legendary', ...(['legendary', 'royal'].includes(chestId) ? ['mythic'] : [])];
  for (const kind of ['frame_shard', 'bioframe_shard']) {
    const ids = missing(kind, rarities);
    groups.push({kind, ids, chance: ids.length ? gate(chance(kind === 'frame_shard' ? 'frameChance' : 'bioChance')[chestId]) : 0});
    rarities.forEach(rarity => missing(kind, [rarity]).forEach(id => targets.push({kind, id, rarity, min: 1, max: 1})));
  }
  const fallback = groups.reduce((p, group) => p * (1 - group.chance), 1);
  const items = targets.map((target, index) => {
    const group = groups.find(g => g.kind === target.kind && g.ids.includes(target.id));
    const normal = group.chance * pick(group.ids.indexOf(target.id), group.ids.length);
    const rescue = fallback * pick(index, targets.length), amountOdds = {};
    const remaining = pools[target.kind][target.id].target - ((inv[fields[target.kind][1]] || {})[target.id] || 0);
    const add = (amount, p) => { amount = Math.min(amount, remaining); amountOdds[amount] = (amountOdds[amount] || 0) + p; };
    if (target.kind === 'frame_shard') {
      const two = gate(Number(source.match(/random\(\)<(\.\d+)\?2:1/)[1]));
      add(1, normal * (1 - two) + rescue); add(2, normal * two);
    } else for (let n = target.min; n <= target.max; n++) add(n, (normal + rescue) * pick(n - target.min, target.max - target.min + 1));
    return {type: target.kind, id: target.id, rarity: target.rarity, amountOdds};
  });
  return {chestId, currency: chest.currency, price: chest.price, goldMin: chest.drops.gold.min,
    goldMax: chest.drops.gold.max, fallbackChance: targets.length ? fallback : 0, items};
}
function fixtures() {
  const cases = [];
  for (const chest of Object.keys(catalogs.CHEST_CATALOG)) {
    const inv = inventory(); inv.ownedSkins = ['classic']; inv.ownedEmojis = ['smile'];
    cases.push({name: chest + '-default', inventory: inv, expected: project(chest, inv)});
  }
  for (const [name, chest, only, cap] of [
    ['one-target', 'common', 'skin:obsidian', false],
    ['one-frame-capped', 'royal', 'frame_shard:rainbow', true],
    ['complete', 'royal', 'none', false],
  ]) {
    const inv = inventory(only);
    if (cap) inv.frameShards.rainbow = 14;
    cases.push({name, inventory: inv, expected: project(chest, inv)});
  }
  const legacy = {ownedSkins: ['classic'], ownedEmojis: ['smile'],
    ownedFrames: ['none'], ownedBioFrames: ['default']};
  cases.push({name: 'legacy-empty-piece-maps', inventory: legacy,
    expected: project('common', legacy)});
  return cases;
}
module.exports = {catalogs, source, pools, fields, chance, inventory, project, fixtures};
if (require.main === module) process.stdout.write(JSON.stringify(fixtures()));
