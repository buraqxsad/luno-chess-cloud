'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {ARENAS} = require('../lib/ranked');
const {ACHIEVEMENT_CATALOG, SEASON_PATH_REWARDS, SEASON_REWARDS} = require('../lib/catalogs');

const flutter = path.resolve(__dirname, '../../luno_chess');
const preview = fs.readFileSync(path.join(flutter, 'lib/data/arena_progression_preview.dart'), 'utf8');

test('V216.1 arena previews exactly match all existing server season-path rewards', () => {
  const rows = [...preview.matchAll(/ArenaPathPreview\('([^']+)',\s*(\d+),\s*(\d+),\s*(\d+)\)/g)]
    .map((m) => ({id: m[1], minTrophies: +m[2], reward: {gold: +m[3], gems: +m[4]}}));
  assert.equal(rows.length, SEASON_PATH_REWARDS.length);
  assert.deepEqual(rows, SEASON_PATH_REWARDS.map((row) => ({
    id: row.id, minTrophies: row.minTrophies,
    reward: {gold: row.reward.gold || 0, gems: row.reward.gems || 0},
  })));
  assert.deepEqual(rows.slice(0, 9).map((row) => row.minTrophies), ARENAS.map((arena) => arena.min));
  assert.equal(rows.at(-1).minTrophies, 5000);
});

test('V216.1 arena achievement previews match server IDs, one-based targets and amounts', () => {
  const rows = [...preview.matchAll(/ArenaAchievementPreview\('([^']+)',\s*(\d+),\s*(\d+),\s*(\d+)\)/g)]
    .map((m) => ({id: m[1], target: +m[2], reward: {gold: +m[3], gems: +m[4]}}));
  const server = Object.entries(ACHIEVEMENT_CATALOG)
    .filter(([, item]) => item.statKey === 'arenaIdx')
    .map(([id, item]) => ({id, target: item.target, reward: {gold: item.reward.gold || 0, gems: item.reward.gems || 0}}));
  assert.deepEqual(rows, server);
  assert.deepEqual(rows.map((row) => row.target), [3, 5, 7, 8, 9]);
});

test('V216.1 season-end tiers are not presented as arena thresholds or promotion grants', () => {
  assert.deepEqual(SEASON_REWARDS.map((tier) => tier.minTrophies), [0, 600, 1000, 1500, 2000, 2750, 3500, 5000]);
  assert.equal(SEASON_REWARDS.at(-1).reward.gold, 100000);
  assert.equal(SEASON_REWARDS.at(-1).reward.gems, 2000);
  const widget = fs.readFileSync(path.join(flutter, 'lib/widgets/arena_progression_benefits.dart'), 'utf8');
  assert.match(widget, /const SeasonScreen\(\)/);
  assert.match(widget, /const AchievementsScreen\(\)/);
  assert.match(widget, /separate server tracks/);
  assert.doesNotMatch(widget, /claimAchievementReward|claimSeason|applyServerState|\.save\(|ownedCards|purchaseSoftItem/);
});
