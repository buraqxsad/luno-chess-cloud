# Original Luno arcane halo

The new halo is original procedural artwork for Luno. It does not replace any
existing card or character art. Blender 5.2.3 LTS renders silver-white faceted
crystals, broken orbits and a fine inner seal with Cycles CPU, 16 samples.
ImageMagick adds a small transparent optical bloom; WebP compresses losslessly.

```bash
source /workspace/toolchains/luno-env.sh
blender -b --factory-startup -noaudio --threads 2 --python-exit-code 1 \
  --python artwork/v237/render_arcane_halo.py -- \
  --out /workspace/luno-upgrade/creative/frames
python3 artwork/v237/assemble_arcane_halo.py /workspace/luno-upgrade/creative/frames
```

Only `assets/native_art/v237-arcane-halo-atlas.webp` ships with the app. It has
16 row-major 192×192 frames in a 4×4 grid: one 768×768 decoded texture (~2.25 MiB)
shared by every card and the guide's finite demo. PNG intermediates and the
editable `.blend` project remain outside the app repository in the review folder.
The renderer needs the managed worker's local socket/network permission for
Blender's runtime initialization; no remote asset download is used.

`LunoArcaneHalo` owns no ticker. The caller supplies finite progress; endpoints,
invalid inputs and reduced-motion mode show no animation. Battle impacts retain
the same public target, clock, cost and duration as before. The ring is open in
the centre and low-opacity, behind the card-specific vector material and piece.
Hardware GPU/FPS acceptance still needs a real device.
