"""Animate the original Luno illustration as a textured Blender puppet.

No source pixels, external artwork, game rules or reward state are changed.
The soft mesh weights add blinking, speech, a nod and a small greeting wave.
"""
import argparse
import math
from pathlib import Path
import sys

import bpy

parser = argparse.ArgumentParser()
parser.add_argument('--out', required=True, type=Path)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
args.out.mkdir(parents=True, exist_ok=True)
source = Path(__file__).resolve().parents[2] / 'assets/native_art/luno-portrait-v212.webp'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 4
scene.render.threads_mode = 'FIXED'
scene.render.threads = 1
scene.render.resolution_x = scene.render.resolution_y = 160
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.world = bpy.data.worlds.new('Transparent portrait stage')
scene.world.color = (0, 0, 0)

n = 96
points = [(x / n * 384, y / n * 384) for y in range(n + 1) for x in range(n + 1)]
verts = [((x - 192) / 192, (192 - y) / 192, 0) for x, y in points]
faces = []
for y in range(n):
    for x in range(n):
        i = y * (n + 1) + x
        faces.append((i, i + n + 1, i + n + 2, i + 1))
mesh = bpy.data.meshes.new('Soft eye, jaw, head and hand weights')
mesh.from_pydata(verts, [], faces)
mesh.update()
uv = mesh.uv_layers.new(name='Original unchanged portrait UV')
for face in mesh.polygons:
    for li in face.loop_indices:
        x, y = points[mesh.loops[li].vertex_index]
        uv.data[li].uv = (x / 384, 1 - y / 384)
obj = bpy.data.objects.new('Luno original illustrated puppet', mesh)
scene.collection.objects.link(obj)
material = bpy.data.materials.new('Original sRGB and alpha, unlit')
material.use_nodes = True
nodes = material.node_tree.nodes
nodes.clear()
texture = nodes.new('ShaderNodeTexImage')
texture.image = bpy.data.images.load(str(source))
texture.interpolation = 'Linear'
emission = nodes.new('ShaderNodeEmission')
transparent = nodes.new('ShaderNodeBsdfTransparent')
mix = nodes.new('ShaderNodeMixShader')
out = nodes.new('ShaderNodeOutputMaterial')
links = material.node_tree.links
links.new(texture.outputs['Color'], emission.inputs['Color'])
links.new(texture.outputs['Alpha'], mix.inputs[0])
links.new(transparent.outputs[0], mix.inputs[1])
links.new(emission.outputs[0], mix.inputs[2])
links.new(mix.outputs[0], out.inputs['Surface'])
obj.data.materials.append(material)
bpy.ops.object.camera_add(location=(0, 0, 4))
scene.camera = bpy.context.object
scene.camera.data.type = 'ORTHO'
scene.camera.data.ortho_scale = 2

def smooth(a, b, v):
    u = max(0, min(1, (v - a) / (b - a)))
    return u * u * (3 - 2 * u)

def rotate(x, y, cx, cy, angle):
    return (cx + (x-cx)*math.cos(angle) - (y-cy)*math.sin(angle),
            cy + (x-cx)*math.sin(angle) + (y-cy)*math.cos(angle))

for frame in range(16):
    t = frame / 15
    envelope = math.sin(math.pi * t) ** 2
    blink = math.exp(-((t-.32)/.045)**2) + math.exp(-((t-.74)/.04)**2)
    talk = (math.sin(t * math.tau * 3) ** 2) * envelope
    for vertex, (x, y) in zip(mesh.vertices, points):
        dx, dy = x, y
        for ex, ey in [(168, 158), (228, 153)]:
            weight = math.exp(-((x-ex)/13)**4 - ((y-ey)/21)**4)
            dy -= (y-ey) * min(1, blink) * .88 * weight
        mouth = math.exp(-((x-199)/19)**4 - ((y-184)/12)**4)
        dy += (y-184) * .20 * talk * mouth
        hand = smooth(254, 286, x) * smooth(194, 217, y) * (1-smooth(260, 290, y))
        hx, hy = rotate(dx, dy, 253, 264, .12 * math.sin(t*math.tau*2) * envelope)
        dx += (hx-dx) * hand
        dy += (hy-dy) * hand
        head = 1 - smooth(210, 245, y)
        hx, hy = rotate(dx, dy, 191, 228, .025 * math.sin(t*math.tau) * envelope)
        dx += (hx-dx) * head
        dy += (hy-dy) * head
        dy -= 2.5 * envelope
        vertex.co = ((dx-192)/192, (192-dy)/192, 0)
    mesh.update()
    scene.frame_set(frame+1)
    scene.render.filepath = str(args.out / f'mentor-{frame:02d}.png')
    bpy.ops.render.render(write_still=True)
texture.image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(args.out.parent / 'mentor-puppet.blend'))
print('Rendered 16 finite portrait frames; original illustration unchanged.')
