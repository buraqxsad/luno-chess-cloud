# V236 Original Asset, Font And License Audit

Audit date: 2026-10-22. Current Flutter root:
`C:\Users\Casper\Documents\Luno Chess\luno-chess-src\luno_chess`.
This worker edited only its audit scripts/reports under `qa/v236`. **No original
asset, font, production source, dependency, signing or platform file was edited
by this worker.** Main's font-notice additions are reconciled below.
No install, network operation, server, emulator, SDK test/build or live operation.

## Outcome

- Current inventory and image decode: PASS, 673/673 images decoded sequentially.
- Current canonical card art: PASS, 24/24 unique mapped paths, all 640x640.
- Current Battle V1 piece paths: PASS, 120/120 resolved, declared and decoded.
- WAV metadata/sample validation: PASS, 60/60 nonempty PCM16 streams.
- Font tables: PASS, 9 TTF and 8 WOFF2 files parsed by FontTools.
- Turkish font coverage: **PARTIAL**. Nunito is complete; the medium/semibold
  SpectralTurkish aliases have a real five-codepoint coverage gap.
- Full font notices, manifest declarations, LicenseRegistry and Settings link:
  **SOURCE VERIFIED** for Nunito, Cinzel and Spectral. Actual APK packaging and
  runtime notice display: **AWAIT MAIN**, not verified by this worker.
- Complete original art/audio provenance: **UNVERIFIED**. This is not a blanket
  legal certification or release clearance.
- Runtime glyph selection, widget rendering, visual/art correctness, listening,
  device playback, animation and physical performance: **NOT RUN**.

The audit makes no source fixes and does not approve release. Its one concrete
font-data finding below is not proof that all Turkish UI text is broken.

## Reproducible Method

Current post-notice run: 2026-10-22 18:01:17.613Z to 18:02:15.150Z, elapsed
57.537 seconds. Pre-notice evidence remains in
`asset-font-audit-pre-notice.json` (finished 17:24:09.163Z).
Existing runtimes only: Node 22.23.3; Python 3.12.14; FontTools 4.64.0 from
`C:\Users\Casper\Documents\Luno Chess\.tools\font-convert\fontTools`.
Sharp is loaded from the exact existing runtime path requested by main.
Complete Sharp/libvips version metadata is in the JSON.

- Sharp concurrency is 1, cache disabled; one image is inspected at a time.
  `metadata()` plus full first-image `stats()` forces pixel decode, not only
  extension/header checks. Every current image has one page.
- Hashing uses a 1 MiB chunk buffer, including the large undeclared legacy ZIP.
  No composite/contact sheet, image rewrite or simultaneous decode batch.
- Python starts only after image inspection completes. WAV samples are streamed
  in 65536-frame chunks. FontTools reads cmap/name/axis tables sequentially.
- Node old-space limit is 128 MiB. This is not a measured total-RSS limit for
  Node, libvips or Python; no fake RAM/performance measurement is claimed.
- `pubspec.yaml` declarations are scanned using strict patterns for its current
  simple directory/font lists. No YAML parser was installed. Dart references
  use bounded source scans and explicit finite-domain expansion, not a full
  Dart parser or actual Flutter execution.

All 755 current asset hashes were compared before/after the run: **0 changed,
0 added, 0 removed during inspection**. Thirteen selected manifest/path/font/audio
and license-registration source hashes also remained
unchanged during inspection. Hashes are retained in JSON. Other chats may edit
unrelated source concurrently; this is not a whole-worktree source freeze.

Comparison with the preserved 753-file pre-notice baseline: **all 753 prior
asset files remain byte-identical**, including all 17 original TTF/WOFF2 fonts,
673 images and 60 WAVs. Only two physical asset files were added by main:
`assets/licenses/cinzel-OFL.txt` and `assets/licenses/spectral-OFL.txt`.
Nunito's already-existing OFL file became declared, not rewritten.

## Current Counts

| Scope | Files | Bytes |
| --- | ---: | ---: |
| All physical files under assets/ | 755 | 203794437 |
| Files selected by current asset/font declarations | 745 | 109465721 |
| Images: 232 PNG + 440 WebP + 1 JPEG | 673 | 106097427 |
| WAV | 60 | 2655274 |
| Declared TTF fonts | 9 | 699860 |
| Declared full font notice texts | 3 | 13160 |

These are fresh source counts, not copied from V235 and not APK/AAB contents.
The declared directories are `assets/native_art/`, its explicit `embedded/`
and `phase2/` subdirectories, `assets/audio/`, and `assets/licenses/`, plus the
nine font files and explicit `assets/fonts/nunito/OFL.txt` declaration.

Ten physical files are not selected by these declarations: 8 WOFF2 variants,
`assets/luno-chess.html` (8224358 bytes), and
`assets/native_art.zip` (85930434 bytes). Thus the large HTML/ZIP are not counted
as current declared native assets. No packaged-artifact inspection was run.

There were **0 decode errors, 0 entirely transparent images and 0 images whose
every channel was constant**. These numerical checks do not prove correct art,
readable baked text, correct crop, sharpness or visual approval. The largest
source image dimensions are 1536x1024, with a 6291456-byte unscaled four-channel
pixel estimate (older set atlases). This is not observed Flutter/GPU allocation;
runtime decode sizing and caches can differ.

Four exact duplicate groups total 159320 duplicate bytes, all Spectral
medium/semibold Latin-versus-Turkish TTF/WOFF2 aliases. No image/audio duplicate
group was found by SHA256. No files were removed. A static-reference miss is
not authorization to delete historical or dynamically used assets.

## Card, Piece And Dynamic References

The JSON records every canonical card and piece path with dimensions, existence,
manifest selection and source evidence:

- `CardId` has 24 entries. The current `battleCardArtAsset` switch in
  `lib/battle_ui/cards.dart` has one unique PNG path for each, all 640x640.
  These are the `battle-card-v204-*.png` assets, not the older 29-card catalog.
- `BattleArt.piecePath` resolves 10 sets x 2 colors x 6 types = **120 paths**.
  Default Luno: 12 `battle-v202b-piece-<side>-<type>.webp`, all 256x256.
  Ottoman/Roma/Brit/Viking/Tasdevri/Samuray/Ice/Dragon/Neon: 108 modern
  `piece-<set>-<side>-<type>-v216.webp`, all 256x320.
- The separate `LunoAssets.pieceForSet` legacy/general resolver also has 120
  valid paths. Its 12 default Luno paths use `piece-luno-*-v22-mobile.webp`;
  its other 108 are the same v216 files. Do not call these 240 distinct active
  sprites: the two resolvers share 108 files (132 distinct files combined).
- All ten current set previews exist at 960x400. Source keeps unknown set input
  on the existing Luno fallback; no Dart/runtime fallback test was executed.
- Additional expansions check all 29 legacy `kCards` art paths, the level icon
  table, avatar/emote/chest filename maps, nine arena paths and 23 finite
  BattleArt/BattleSkin/effect paths. Audio AssetSource paths are checked too.
- A total of **568 distinct supported literal/expanded references** exist and
  are selected by the current declarations: 0 missing, 0 undeclared. This
  includes the three font notice text references added to the source scan.

Limit: broad source scanning includes inactive/legacy Dart files and is not a
proof of production reachability. Seven interpolated template strings are
retained in JSON, including the general achievement-ID and arbitrary BattleArt
name templates. Known finite paths are expanded above; arbitrary/future server
IDs and all runtime string combinations are not exhaustively certified. In
particular, a supported-template scan cannot prove that every dynamically
supplied achievement name is a valid image. No speculative missing-asset bug
was created from this limitation.

## Font Coverage And Fallback Chain

Tested Turkish-specific set: U+00C7/U+00E7, U+011E/U+011F, U+0130/U+0131,
U+00D6/U+00F6, U+015E/U+015F, U+00DC/U+00FC. JSON includes every codepoint,
glyph name, full font hash, copyright, license metadata and variable axes.

| Declared family/file | Unicode cmap count | Turkish result |
| --- | ---: | --- |
| Nunito variable | 938 | All 12 present; all basic Latin present |
| Cinzel Latin | 220 | Missing U+011E, U+011F, U+0130, U+015E, U+015F |
| CinzelTurkish | 125 | Supplies those five; complementary subset, not a complete standalone font |
| Spectral regular Latin (400) | 230 | Missing the same five |
| SpectralTurkish regular (400) | 312 | Supplies those five; complementary subset |
| Spectral medium Latin (500) | 230 | Missing the same five |
| SpectralTurkish medium (500) | 230 | Identical to Latin; still missing those five |
| Spectral semibold Latin (600) | 230 | Missing the same five |
| SpectralTurkish semibold (600) | 230 | Identical to Latin; still missing those five |

**AF236-01, font-data coverage gap:** the actual 500/600 Turkish TTF files are
byte-identical to their Latin counterparts, so registering them as
SpectralTurkish does not supply the absent codepoints at those weights. The
corresponding WOFF2 pairs are also identical. No file was replaced. Correct
same-family extended glyph files and their distribution notices would need
explicitly authorized, provenance-checked follow-up, not an unverified download
or a font-family rename.

The regular Spectral pair and the Cinzel pair together cover all 12 tested
Turkish codepoints. Their Turkish subset files alone omit some common Latin
letters; this is expected complementary-subset behavior, not evidence they
should be used as the primary full alphabet.

Current source chain in `lib/theme/luno_theme.dart`:

- `LunoTheme.darkFor`: local **Nunito primary in both languages**. Body fallback
  is SpectralTurkish for English and Spectral for Turkish, exactly as written.
- Shared LunoType body/bodyMuted/button/label use Nunito then SpectralTurkish.
  screenTitle/sectionTitle use Nunito. Nunito itself covers all tested Turkish
  glyphs, so the Spectral gap does not demonstrate missing default body text.
- Display/stat styles use Cinzel then CinzelTurkish. Timer style uses Spectral
  then SpectralTurkish. Some direct Cinzel overrides elsewhere do not repeat
  that explicit fallback; inherited/system selection was not runtime-tested.
- The Nunito variable axis is wght 200-1000; Cinzel is wght 400-900. Spectral
  declares static 400/500/600 files. Metadata/registrations are not evidence of
  actual Android shaping, weight synthesis, line metrics or visual consistency.

No claim of a current whole-app Turkish rendering failure is made. Real TR/EN
widget/device comparisons remain needed for the styles that exercise fallback.

## Font Notice Reconciliation

The pre-change gaps were real at the original checkpoint: only embedded
license URLs were found for Cinzel/Spectral, and Nunito's full OFL text existed
but was not selected by the manifest. They are retained as **historical
findings**, not current source blockers.

Main fetched the full OFL texts from these official Google Fonts repository
URLs, supplied by main and recorded here without a new network fetch:

- [Cinzel OFL](https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/OFL.txt)
- [Spectral OFL](https://raw.githubusercontent.com/google/fonts/main/ofl/spectral/OFL.txt)

Current local checks confirm all three files contain the full OFL 1.1 sections
and family copyright matching the embedded font metadata. The manifest selects
all three. `lib/services/luno_font_licenses.dart` maps all families, adds an
idempotent LicenseRegistry producer, and loads the full text with rootBundle
into LicenseEntryWithLineBreaks. `lib/main.dart` calls registration after
WidgetsFlutterBinding initialization and before runApp. The current Settings
entry `settings-licenses` calls showLicensePage with applicationName LUNO Chess.
This is **source verification**, not an executed widget or Android UI test.

| Notice | Bytes | SHA256 |
| --- | ---: | --- |
| Nunito existing OFL.txt | 4385 | 580df76c95a1ec5ab878ceb25bb3d85c6a076804e9c970c8c6972aea775fdf65 |
| assets/licenses/cinzel-OFL.txt | 4383 | f2b3029aba64c378bf0963b62945eee15e564fe4330b934c8f2eb058282b5e83 |
| assets/licenses/spectral-OFL.txt | 4392 | 501d6ceca8e552630fe3aa9442b9a818565680a1a2f79f3fb8c13d6f309a9e98 |

Main still owns actual APK/AAB asset inclusion and installed license-page
verification. The Spectral 500/600 glyph-data issue above is unchanged because
**none of the original font files changed**. Closing notice delivery at source
level does not supply missing glyphs or establish all media rights.

## Actual Local License Evidence

| Family / media | Evidence present | What remains unverified |
| --- | --- | --- |
| Nunito | Existing full OFL 1.1 text and matching 2014 copyright; now declared and registered for display | Final APK inclusion and actual installed notice display await main |
| Cinzel / CinzelTurkish | New full OFL 1.1 text from official Google Fonts URL supplied by main; matching 2020 copyright; declared and registered | Final APK inclusion and actual installed notice display await main |
| Spectral / SpectralTurkish | New full OFL 1.1 text from official Google Fonts URL supplied by main; matching 2017 copyright; declared and registered | Final APK inclusion and actual installed notice display await main |
| Original native art | Local ImageGen prompt/source notes exist for some versions, including v211/v212 | Not a complete per-file provenance or rights-grant inventory for all 673 images |
| Audio | Local procedural generation scripts exist, including generate_audio_assets.dart and build_card_audio_v210.cjs | Scripts were not executed and do not establish authorship/license chain for every current WAV |
| Legacy art-source material | art-source/native-art-legacy/LICENSE.txt: MIT, 2013 Panayiotis Lipiridis | No per-file mapping proves it covers all original/runtime artwork; it must not be applied blanket-wide |

The current JSON preserves four discovered standalone license texts and hashes
(three font notices plus the legacy MIT notice);
embedded font metadata is recorded independently for all 17 font files. No
external license page was fetched by this worker. The reported official fetches
were performed by main. Source-level full-text delivery is now verified, but
it is not blanket verification of every license condition or release
compliance. **Complete original artwork/audio provenance remains UNVERIFIED**;
the font notice change does not resolve that separate evidence gap. No existing
license, attribution or provenance file was edited or removed by this worker.

## WAV Results

All 60 files are mono, 22050 Hz, uncompressed signed PCM16. Total: 1326317
frames, 60.150430839 seconds, 2655274 source bytes. Individual duration range:
0.090022676 to 12 seconds. Every sample stream has the declared frame length;
none is entirely silent and none contains a full-scale -32768/+32767 sample.
Per-file frames/duration/peak/RMS and hashes are in JSON.

This validates metadata and sample integrity only. No listening or native
playback was performed; sound quality, loop joins, latency, gain balance,
clipping below full scale, lifecycle behavior and device audio focus remain
NOT RUN. It does not replace section 13's real-device sound/animation review.

## Files And Commands

Sidecar-only paths:

- `qa/v236/asset-font-audit.cjs`
- `qa/v236/asset-font-audit.py`
- `qa/v236/asset-font-audit.json` (705971 bytes at this checkpoint)
- `qa/v236/asset-font-audit-pre-notice.json` (preserved original baseline)
- `qa/v236/asset-font-audit.md`

Actual final command, serial and self-contained; run only when main has a free
light-audit slot. It rewrites only the current JSON in its own QA directory and
preserves a pre-notice baseline once when the old 753-file report is present:

```powershell
Set-Location -LiteralPath 'C:\Users\Casper\Documents\Luno Chess\luno-chess-src\luno_chess'
$node='C:\Users\Casper\Documents\Luno Chess\.tools\node22\node-v22.23.3-win-x64\node.exe'
& $node --max-old-space-size=128 qa/v236/asset-font-audit.cjs
```

Current post-notice run: exit 0, 755 physical / 745 declared files, 673 decoded
images, 24 card and 120 active piece paths, 60 WAVs, 17 parsed fonts, zero
decode/reference errors. The three complete notice texts and registry/startup/
Settings source checks also passed. Pre-notice scans completed successfully
and their historical gaps are reconciled above. No Flutter/backend test suite,
generator, APK verifier or runtime notice-page test was launched by this worker.
