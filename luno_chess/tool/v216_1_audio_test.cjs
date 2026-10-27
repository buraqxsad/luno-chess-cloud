const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {cues, render, metrics, qa, root, assets, hash} = require('./v216_1_audio.cjs');
const before = JSON.parse(fs.readFileSync(path.join(qa, 'before/audio/metrics.json'))).rows;
const after = JSON.parse(fs.readFileSync(path.join(qa, 'after/audio/metrics.json'))).rows;

test('42 before and 60 after WAVs are unique, valid mono PCM16 with zero clipping', () => {
  assert.equal(before.length, 42); assert.equal(after.length, 60);
  for (const group of [before, after]) {
    assert.equal(new Set(group.map(r => r.sha256)).size, group.length);
    for (const row of group) {
      assert.equal(row.rate, 22050); assert.equal(row.channels, 1); assert.equal(row.bits, 16);
      assert.equal(row.clipped, 0); assert.ok(row.rms > 0 && Number.isFinite(row.rms));
      assert.ok(row.centroidHz > 0 && row.centroidHz < 11025);
    }
  }
});

test('all 26 authored cues regenerate byte-identically and have bounded transients', () => {
  for (const name of Object.keys(cues)) {
    const bytes = fs.readFileSync(path.join(assets, `${name}.wav`));
    assert.ok(render(name).equals(bytes), name);
    const row = metrics(`${name}.wav`, bytes);
    assert.ok(row.peak <= .321, name);
    assert.ok(Math.abs(row.dc) < .0001, `${name} DC`);
    assert.ok(Math.abs(row.first) < .0001 && Math.abs(row.last) < .0001, `${name} endpoints`);
    assert.ok(row.onsetMs < 1, `${name} onset`);
  }
});

test('only the eight declared original WAVs changed and no original duration moved', () => {
  const changed = before.filter(old => old.sha256 !== after.find(r => r.name === old.name).sha256);
  assert.deepEqual(changed.map(r => r.name).sort(), ['capture.wav', 'mine_triggered.wav', 'move.wav',
    'spell_board_seal.wav', 'spell_fate_exchange.wav', 'spell_freeze.wav', 'spell_mine.wav', 'victory.wav'].sort());
  for (const old of before) {
    assert.ok(Math.abs(old.durationMs - after.find(r => r.name === old.name).durationMs) < .05, old.name);
    assert.equal(hash(fs.readFileSync(path.join(qa, 'before/audio/wavs', old.name))), old.sha256);
  }
});

test('30 preserved procedural originals still match their V209/V210/V214 generators', () => {
  let checked = 0;
  for (const script of ['build_battle_audio_v209.cjs', 'build_card_audio_v210.cjs', 'build_semantic_audio_v214.cjs']) {
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, script), 'utf8'), {
      require(name) {
        if (['fs', 'node:fs'].includes(name)) return {writeFileSync(file, bytes) {
          const name = path.basename(file);
          if (Object.hasOwn(cues, name.replace('.wav', ''))) return;
          assert.ok(bytes.equals(fs.readFileSync(path.join(assets, name))), name); checked++;
        }};
        if (['path', 'node:path'].includes(name)) return path;
        if (name === 'node:crypto') return require('node:crypto');
        throw Error(`Unexpected dependency: ${name}`);
      },
      __dirname, Buffer, process: {stdout: {write() {}}},
    });
  }
  assert.equal(checked, 30);
});

test('fourteen emotes have different authored waveforms and non-copied spectral/envelope signatures', () => {
  const rows = after.filter(r => /^emote_(?!unlock)/.test(r.name));
  assert.equal(rows.length, 14);
  assert.equal(new Set(rows.map(r => r.sha256)).size, 14);
  const signatures = rows.map(r => `${r.centroidHz.toFixed(1)}:${r.windows20ms.map(v => v.toFixed(5)).join(',')}`);
  assert.equal(new Set(signatures).size, 14);
  for (const row of rows) assert.ok(row.rms <= .035 && row.durationMs <= 980.1, row.name);
});

test('legacy loudness outliers move/capture/victory are at least 9 dB closer to spell palette', () => {
  for (const name of ['move.wav', 'capture.wav', 'victory.wav']) {
    const old = before.find(r => r.name === name), next = after.find(r => r.name === name);
    assert.ok(old.rmsDbfs - next.rmsDbfs > 9, name);
    assert.ok(next.rmsDbfs >= -28 && next.rmsDbfs <= -24, name);
  }
});

test('all new assets are included by the existing audio directory declaration', () => {
  assert.match(fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8'), /- assets\/audio\//);
});
