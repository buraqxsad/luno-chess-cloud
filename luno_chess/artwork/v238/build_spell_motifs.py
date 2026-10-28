"""Compose transparent optical bloom and lossless 4x4 WebP atlases."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('frames', type=Path)
args = parser.parse_args()
assembler = Path(__file__).resolve().parents[1] / 'v237/assemble_arcane_halo.py'
assets = Path(__file__).resolve().parents[2] / 'assets/native_art'
for motif in ['crystal', 'binding', 'veil']:
    # The original assembler writes adjacent intermediates; isolate each family.
    subprocess.run(['python3', str(assembler), str(args.frames / motif), '--asset',
                    str(assets / f'v238-{motif}-atlas.webp')], check=True)
