# Tutorial Luno puppet

The original `assets/native_art/luno-portrait-v212.webp` stays byte-identical.
Blender 5.2.3 animates it on an original soft-weighted UV mesh: two short blinks,
small mouth/speech deformation, a nod and a greeting-hand wave. No external art
or animation package is required. ImageMagick and WebP tools pack 16 transparent
160×160 frames into one lossless 640×640 atlas.

```bash
source /workspace/toolchains/luno-env.sh
blender --background -noaudio --threads 1 --python artwork/tutorial_live/render_mentor.py -- --out /tmp/luno-mentor/frames
python3 artwork/tutorial_live/assemble_mentor.py /tmp/luno-mentor/frames --preview /tmp/luno-mentor/preview.webp
```

Run from `luno_chess/`. Host local IPC must be permitted by its sandbox. In this
worker an initial run exported every frame and saved the blend, then hung during
unavailable PulseAudio teardown; that process was stopped after export. The final
run with local IPC and `-noaudio` completed with exit0; original and repeated
atlases have the same SHA-256. Logs and `.blend` are outside Git in
`/workspace/luno-review/tutorial-live/art/`.

`asset-provenance.json` records hashes and exact sizes. File size:324110B;
decoded RGBA:1638400B (1.5625MiB), not a device RAM/GPU measurement. The original
portrait is the rest/reduced-motion/loading fallback. One cached texture is
cropped, rather than decoding separate frame files at runtime.

Each gesture is finite1100ms. Tutorial mentors sleep4700ms between optional idle
gestures; there is no continuous ticker between gestures. New instructions
restart the finite cue, unchanged-parent rebuilds keep the sleeping deadline.
Background, covered route, disabled TickerMode, reduced motion and disposal stop
motion and cancel timers. Resume waits for a fresh idle interval. No match,
account, purchase, reward or tutorial-completion state is owned by this artwork.

This is a Flutter/widget verified visual change. Native performance, the V240
startup raster crash and physical-device acceptance remain separate open gates.
