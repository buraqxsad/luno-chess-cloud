"""Pack the finite Blender portrait into one lossless 640px WebP texture."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('frames', type=Path)
parser.add_argument('--preview', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
asset = root / 'assets/native_art/tutorial-luno-live-atlas.webp'
frames = [args.frames / f'mentor-{i:02d}.png' for i in range(16)]
assert all(frame.exists() for frame in frames)
atlas = args.frames.parent / 'mentor-atlas.png'
subprocess.run(['magick', 'montage', *map(str, frames), '-tile', '4x4',
                '-geometry', '160x160+0+0', '-background', 'none', str(atlas)], check=True)
subprocess.run(['cwebp', '-quiet', '-lossless', '-z', '9', str(atlas), '-o', str(asset)], check=True)
if args.preview:
    subprocess.run(['img2webp', '-loop', '0', '-d', '73', *map(str, frames), '-o', str(args.preview)], check=True)
source = root / 'assets/native_art/luno-portrait-v212.webp'
record = {'source_asset': source.relative_to(root).as_posix(),
          'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'atlas_asset': asset.relative_to(root).as_posix(),
          'atlas_sha256': hashlib.sha256(asset.read_bytes()).hexdigest(),
          'atlas_bytes': asset.stat().st_size, 'frames': 16, 'frame_size': [160, 160],
          'decoded_rgba_bytes': 640 * 640 * 4, 'runtime_duration_ms': 1100,
          'physical_device_performance': 'NOT RUN'}
(Path(__file__).parent / 'asset-provenance.json').write_text(json.dumps(record, indent=2)+'\n')
print(json.dumps(record, indent=2))
