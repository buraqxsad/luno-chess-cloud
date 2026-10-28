"""Assemble Blender RGBA frames with installed ImageMagick and WebP tools."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("frames", type=Path)
parser.add_argument("--asset", type=Path,
                    default=Path(__file__).resolve().parents[2] /
                    "assets/native_art/v237-arcane-halo-atlas.webp")
args = parser.parse_args()
glow = args.frames.parent / "glow"
glow.mkdir(parents=True, exist_ok=True)
frames = []
for index in range(16):
    source = args.frames / f"halo-{index:02d}.png"
    destination = glow / source.name
    subprocess.run([
        "magick", str(source), "(", "+clone", "-channel", "RGBA",
        "-blur", "0x1.5", "-channel", "A", "-evaluate", "multiply", "0.55",
        "+channel", ")", "-compose", "DstOver", "-composite", str(destination)
    ], check=True)
    frames.append(str(destination))
atlas = args.frames.parent / "arcane-halo-atlas.png"
subprocess.run(["magick", "montage", *frames, "-tile", "4x4", "-geometry",
                "192x192+0+0", "-background", "none", str(atlas)], check=True)
args.asset.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(["cwebp", "-quiet", "-lossless", "-z", "9", str(atlas),
                "-o", str(args.asset)], check=True)
print(f"Created {args.asset} ({args.asset.stat().st_size} bytes)")
