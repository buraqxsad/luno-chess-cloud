# V238 card effects

Original procedural art: `render_spell_motifs.py` uses Blender 5.2.3 LTS,
Cycles CPU / 16 samples to render three open-centred motifs (faceted crystals,
interlocking metal links, spectral light ribbons). No external image is edited.
`build_spell_motifs.py` uses ImageMagick and lossless WebP through the preserved
V237 assembler. Its adjacent glow/atlas intermediates are reused sequentially;
each final motif WebP is exported before the next family is assembled.

```sh
source /workspace/toolchains/luno-env.sh
blender -b --factory-startup -noaudio --threads 2 --python-exit-code 1 \
  --python artwork/v238/render_spell_motifs.py -- \
  --out /workspace/luno-v238/creative/frames
python3 artwork/v238/build_spell_motifs.py /workspace/luno-v238/creative/frames
```

Each atlas is 768×768 / 16 frames / 192px cells. New compressed sizes are
140332 (crystal), 214622 (binding), 66194 (veil) bytes; together 421148 bytes.
Including the existing V237 arcane atlas, the four decoded RGBA textures use
9 MiB. Warm-up reads only the player's own known hand or an accepted public cast.
No opponent hand/deck contents are used to choose art. There are no new tickers,
dependencies or repeating particle systems. The existing accepted-cast clock,
1.4–2.2s durations and accessibility/lifecycle controls remain authoritative.

Every card also has its own finite vector choreography in
`lib/battle_ui/spell_choreography.dart`, replacing the former generic category
accent. It keeps a clear centre for pieces and preserves the original card art
and primary spell material. A Mine cast explicitly arms a device; it does not
present a detonation. Knowledge cards do not depict private card faces.

Sources/final WebPs ship in Git; raw PNGs, Blender projects and review captures
remain outside the app source under `/workspace/luno-v238/`. Software widget
renders establish appearance and bounded assets, not native GPU/FPS acceptance.
