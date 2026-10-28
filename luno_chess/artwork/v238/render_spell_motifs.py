"""Original finite Luno spell motifs, Cycles CPU; no external art inputs."""
import argparse
import math
from pathlib import Path
import sys

import bpy

parser = argparse.ArgumentParser()
parser.add_argument('--out', required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
output = Path(args.out).resolve()


def material(name, emission, metallic):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (.8, .87, 1, 1)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = .23
    shader.inputs['Emission Color'].default_value = (.85, .93, 1, 1)
    shader.inputs['Emission Strength'].default_value = emission
    return mat


for motif in ['crystal', 'binding', 'veil']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 192
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('Quiet world')
    scene.world = world
    world.color = (.025, .025, .025)
    pearl = material('Runtime-tinted pearl', .28, .75)
    energy = material('Fine energy', 2.2, .15)
    bpy.ops.object.empty_add()
    root = bpy.context.object
    root.name = f'Luno {motif} finite motif'
    animated = []

    if motif == 'crystal':
        for index in range(12):
            angle = index * math.tau / 12
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1)
            obj = bpy.context.object
            obj.parent = root
            obj.data.materials.append(pearl)
            obj.scale = (.07, .10, .25 + index % 3 * .055)
            obj.rotation_euler = (.8 * math.sin(angle), .8 * math.cos(angle), angle)
            animated.append((obj, angle, .96 + (index % 2) * .13))
    elif motif == 'binding':
        for index in range(16):
            angle = index * math.tau / 16
            bpy.ops.mesh.primitive_torus_add(
                major_segments=16, minor_segments=6,
                major_radius=.145, minor_radius=.035,
                location=(math.cos(angle), math.sin(angle), 0),
            )
            obj = bpy.context.object
            obj.parent = root
            obj.data.materials.append(pearl)
            obj.scale = (1.25, .8, 1)
            obj.rotation_euler = ((index % 2) * .9, .18, angle + math.pi / 2)
            animated.append((obj, angle, 1.0))
    else:
        for index in range(6):
            curve = bpy.data.curves.new('Spectral wisp', 'CURVE')
            curve.dimensions = '3D'
            curve.bevel_depth = .012 + (index % 2) * .007
            curve.bevel_resolution = 2
            spline = curve.splines.new('POLY')
            spline.points.add(47)
            for n, point in enumerate(spline.points):
                u = n / 47
                angle = index * math.tau / 6 + u * 1.15
                radius = .64 + .54 * u
                point.co = (radius * math.cos(angle), radius * math.sin(angle),
                            .12 * math.sin(u * math.pi), 1)
            obj = bpy.data.objects.new('Open-centred light ribbon', curve)
            scene.collection.objects.link(obj)
            obj.parent = root
            obj.data.materials.append(energy)

    bpy.ops.object.camera_add(location=(0, 0, 6))
    camera = bpy.context.object
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 3.4
    scene.camera = camera
    bpy.ops.object.light_add(type='AREA', location=(-2, -3, 5))
    bpy.context.object.data.energy = 500
    bpy.context.object.data.size = 2.5
    folder = output / motif
    folder.mkdir(parents=True, exist_ok=True)
    for frame in range(16):
        t = frame / 15
        opening = .68 + .32 * (1 - (1 - t) ** 3)
        root.scale = (opening, opening, opening)
        root.rotation_euler.z = t * (.42 if motif == 'binding' else .85)
        for obj, angle, radius in animated:
            obj.location = (math.cos(angle) * radius, math.sin(angle) * radius,
                            .04 * math.sin(angle + t * math.pi))
            if motif == 'crystal':
                obj.rotation_euler.z = angle + t * .75
        scene.render.filepath = str(folder / f'halo-{frame:02d}.png')
        bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output / f'{motif}.blend'))
