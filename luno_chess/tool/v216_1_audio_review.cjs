const fs = require('node:fs');
const path = require('node:path');
const {cues, decode, qa, root, assets, hash} = require('./v216_1_audio.cjs');
const before = JSON.parse(fs.readFileSync(path.join(qa, 'before/audio/metrics.json'))).rows;
const after = JSON.parse(fs.readFileSync(path.join(qa, 'after/audio/metrics.json'))).rows;
const cases = {
  'accepted capture + public Mine activation + check': [['capture', 0], ['mine_triggered', 80], ['check', 120]],
  'cast + Freeze impact': [['card_cast', 0], ['spell_freeze', 441]],
  'cast + Board Seal impact': [['card_cast', 0], ['spell_board_seal', 623]],
  'cast + Fate Exchange impact': [['card_cast', 0], ['spell_fate_exchange', 623]],
  'last capture + victory': [['capture', 0], ['victory', 400]],
  'emote + capture + check': [['emote_thunder', 0], ['capture', 0], ['check', 120]],
};
const mixes = [];
for (const phase of ['before', 'after']) {
  for (const [name, sequence] of Object.entries(cases)) {
    if (phase === 'before' && sequence.some(([cue]) => cue.startsWith('emote_'))) continue;
    const dir = phase === 'before' ? path.join(qa, 'before/audio/wavs') : assets;
    const music = decode(fs.readFileSync(path.join(dir, 'battle_loop.wav')));
    const tracks = sequence.map(([cue, at]) => ({samples: decode(fs.readFileSync(path.join(dir, `${cue}.wav`))), start: Math.round(at * 22.05)}));
    const length = Math.max(...tracks.map(t => t.start + t.samples.length));
    let peak = 0, sum = 0, clipped = 0;
    for (let i = 0; i < length; i++) {
      let sample = music[i % music.length] * .82;
      for (const track of tracks) sample += (track.samples[i - track.start] || 0) * .82;
      peak = Math.max(peak, Math.abs(sample)); sum += sample * sample;
      if (Math.abs(sample) >= 1) clipped++;
    }
    mixes.push({phase, name, peak, rms: Math.sqrt(sum / length), clipped, musicVolume: .82, effectsVolume: .82,
      scope: 'Synthetic aligned PCM stress mix, not native playback, all phase offsets or perceived masking'});
  }
}
if (mixes.some(m => m.clipped)) throw Error('Selected stress mix clips');
fs.writeFileSync(path.join(qa, 'audio-mix-checks.json'), JSON.stringify(mixes, null, 2));

const changed = before.filter(old => old.sha256 !== after.find(r => r.name === old.name).sha256);
const comparisons = ['# Before / After Audio', '', 'RMS is raw signal energy, not LUFS or human loudness.', '',
  '| WAV | RMS before dBFS | RMS after dBFS | Peak before dBFS | Peak after dBFS |',
  '| --- | ---: | ---: | ---: | ---: |', ...changed.map(old => {
    const next = after.find(r => r.name === old.name);
    return `| ${old.name} | ${old.rmsDbfs.toFixed(1)} | ${next.rmsDbfs.toFixed(1)} | ${old.peakDbfs.toFixed(1)} | ${next.peakDbfs.toFixed(1)} |`;
  }), '', '34 original files remain byte-identical. New cues are authored candidates integrated for review, not audition-approved.',
  'Remaining review flags: UI click and defeat retain the old high RMS; music loops are unchanged.',
  'Fog is intentionally noise-dominant (>4 kHz energy 29.8%); no listening-based harshness conclusion is possible.',
  'Pawn Advance/Rook Bend start about 20 ms after impact; Hunt Vow about 10 ms. Other original onsets are below 1 ms.',
  'No card timing, visibility projection or battle cue scheduling was changed.'];
fs.writeFileSync(path.join(qa, 'audio-comparison.md'), comparisons.join('\n') + '\n');

const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
const rows = Object.keys(cues).map(name => {
  const original = before.some(r => r.name === `${name}.wav`);
  return `<tr><th>${escape(name)}</th><td>${original ? `<audio controls preload="none" src="before/audio/wavs/${name}.wav"></audio>` : 'New identity'}</td><td><audio controls preload="none" src="../../assets/audio/${name}.wav"></audio></td><td><input type="checkbox" aria-label="Audition accepted ${escape(name)}"></td></tr>`;
});
fs.writeFileSync(path.join(qa, 'audio-audition.html'), `<!doctype html><html lang="en"><meta charset="utf-8"><title>Luno V216.1 Audio Audition</title><style>body{font:15px system-ui;background:#151a1e;color:#eef5f7;margin:24px}h1{font-size:24px}table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:8px;border-bottom:1px solid #485257}audio{max-width:260px;width:100%}input{width:24px;height:24px}p{max-width:900px}</style><h1>Luno V216.1 Audio Audition</h1><p>Human audition pending. No autoplay. Compare at the same device volume; checkbox state is local and is not a saved approval record.</p><table><thead><tr><th>Cue</th><th>V216</th><th>Authored candidate</th><th>Accept</th></tr></thead><tbody>${rows.join('')}</tbody></table></html>`);

const checklist = ['# Physical Audition Checklist', '', 'Status: NOT EXECUTED. No human hearing approval is claimed.', '',
  '- [ ] Headphones and phone speaker, fixed device volume: compare all 8 replaced cues using audio-audition.html.',
  '- [ ] Move/capture: tactile contact, no buzzy/synthetic tail; capture remains identifiable without overpowering spells.',
  '- [ ] Mine placement vs public activation: clearly different; hidden mine coordinates and opponent private draws remain silent.',
  '- [ ] Freeze vs Board Seal vs Fate Exchange: crystal / heavy seal / paired crossing gestures remain recognizable on a small speaker.',
  '- [ ] Card, costume, emote unlock and costume equip: four distinct short identities; one confirmed reveal gives one cue.',
  '- [ ] Win vs defeat/draw: check emotional identity and balance. Old UI-click/defeat RMS remains higher and needs a listening decision.',
  '- [ ] All 14 emotes: recognizable sound/motion pairing; rare/legendary/mythic feel distinct, not louder spam.',
  '- [ ] SFX levels OFF/LOW/MEDIUM/HIGH plus music: listen to capture+Mine+check and cast+impact without masking or distortion.',
  '- [ ] Sound OFF and emote-channel mute: no cue starts; toggling ON does not revive an old cue.',
  '- [ ] Pause/resume, route hide, reconnect/account switch: no stale cue or motion resumes; cancelEmotes leaves battle warning/music intact.',
  '- [ ] Reduced Motion: static complete art, one semantic sound at real accepted impact, no phantom flight delay.',
  '- [ ] Actual device timing/focus: gesture/impact synchronization, Bluetooth and interruption behavior; record device, OS and result.',
  '', 'Listen to remaining 34 originals too: full technical inventory is in before/audio/inventory.md and after/audio/inventory.md.',
  'Do not sign off subjective quality, native latency, focus or perceived masking from metrics alone.'];
fs.writeFileSync(path.join(qa, 'audio-audition-checklist.md'), checklist.join('\n') + '\n');
fs.writeFileSync(path.join(qa, 'audio-source-freeze.json'), JSON.stringify({
  generatedUtc: new Date().toISOString(),
  sources: Object.fromEntries(['lib/services/luno_audio_service.dart', 'lib/widgets/cosmetic_emote_art.dart',
    'lib/battle_ui/audio_feedback.dart', 'test/v216_1_audio_emotes_test.dart', 'test/v216_1_emote_capture_test.dart',
    'tool/v216_1_audio.cjs', 'tool/v216_1_audio_test.cjs', 'tool/v216_1_audio_review.cjs'].map(file =>
      [file, hash(fs.readFileSync(path.join(root, file)))])),
  audio: Object.fromEntries(after.map(r => [r.name, r.sha256])),
  battleAudioUnchanged: hash(fs.readFileSync(path.join(root, 'lib/battle_ui/audio_feedback.dart'))) ===
    JSON.parse(fs.readFileSync(path.join(qa, 'before/audio/metrics.json'))).sourceStamp['lib/battle_ui/audio_feedback.dart'],
}, null, 2));

// This mode verifies real Flutter outputs only after the coordinated capture run.
async function reviewRenders() {
  const sharp = require('C:/Users/Casper/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
  const review = [];
  for (const phase of ['before', 'after']) {
    const dir = path.join(qa, phase, 'emotes');
    if (!fs.existsSync(dir)) throw Error(`No actual ${phase} Flutter renders; run coordinated capture first`);
    const pngs = fs.readdirSync(dir).filter(n => n.endsWith('.png'));
    if (pngs.length !== 74) throw Error(`Expected 74 ${phase} captures, got ${pngs.length}`);
    for (const file of fs.readdirSync(dir).filter(n => n.endsWith('-source.json'))) {
      const record = JSON.parse(fs.readFileSync(path.join(dir, file)));
      for (const [name, source] of Object.entries(record.sources)) {
        if (fs.readFileSync(path.join(root, name), 'utf8') !== source) throw Error(`Render/source drift: ${name}`);
      }
    }
    for (const png of pngs) {
      const stats = await sharp(path.join(dir, png)).stats();
      if (stats.channels.slice(0, 3).every(c => c.stdev < 2)) throw Error(`Blank render ${png}`);
      review.push({phase, png, sha256: hash(fs.readFileSync(path.join(dir, png))), stdev: stats.channels.slice(0, 3).map(c => c.stdev)});
    }
    const tiles = [];
    for (const at of [0, 120, 300, 600, 1200]) {
      const file = `en-320x568-1.0-${at}.png`;
      tiles.push({input: await sharp(path.join(dir, file)).resize({width: 240}).png().toBuffer(), left: tiles.length * 240, top: 0});
    }
    await sharp({create: {width: 1200, height: 426, channels: 4, background: '#151a1e'}}).composite(tiles).png().toFile(path.join(qa, `${phase}-emote-frames.png`));
  }
  fs.writeFileSync(path.join(qa, 'emote-render-review.json'), JSON.stringify(review, null, 2));
  console.log(`Verified ${review.length} nonblank source-matched Flutter PNGs. Human visual inspection still required.`);
}
console.log(JSON.stringify({changedOriginals: changed.length, preservedOriginals: 42 - changed.length, authored: Object.keys(cues).length, selectedPcmMixes: mixes.length, clipped: 0}));
if (process.argv.includes('--renders')) reviewRenders().catch(e => { console.error(e); process.exitCode = 1; });
