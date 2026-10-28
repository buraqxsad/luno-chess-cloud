"""Original Luno spell halo, rendered in Blender; no third-party artwork.

blender -b --factory-startup --threads 2 -P render_arcane_halo.py -- --out DIR
The 16 RGBA frames form a 4x4 atlas, row-major, 192 px per cell.
"""
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument("--out", required=True)
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
out = Path(args.out).resolve()
out.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 192
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.render.threads_mode = "FIXED"
scene.render.threads = 2
scene.world.color = (0.02, 0.02, 0.02)
scene.view_settings.view_transform = "Standard"

def material(name, emission, metallic=0.0):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.8, 0.86, 1.0, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = 0.24
    shader.inputs["Emission Color"].default_value = (0.85, 0.93, 1.0, 1.0)
    shader.inputs["Emission Strength"].default_value = emission
    return result

light_material = material("Silver-white energy (runtime tinted)", 3.0)
crystal_material = material("Faceted pearl", 0.55, 0.65)
soft_material = material("Inner filigree", 1.1, 0.45)
bpy.ops.object.empty_add()
root = bpy.context.object
root.name = "Arcane halo — one finite cast"

def arc(name, radius, start, length, thickness, z, mat):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = thickness
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    count = 44
    spline.points.add(count)
    for index, point in enumerate(spline.points):
        angle = start + length * index / count
        point.co = (radius * math.cos(angle), radius * math.sin(angle), z, 1)
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.parent = root
    return obj

for index in range(3):
    arc("Broken orbit", 1.05, index * math.tau / 3, math.tau * 0.235,
        0.016, 0.03, light_material)
    arc("Reverse orbit", 0.83, index * math.tau / 3 + 0.4, math.tau * 0.20,
        0.009, 0.1, soft_material)
arc("Fine inner seal", 0.64, 0, math.tau, 0.007, 0, soft_material)
crystals = []
for index in range(8):
    angle = index * math.tau / 8
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1)
    crystal = bpy.context.object
    crystal.name = "Orbit crystal"
    crystal.data.materials.append(crystal_material)
    crystal.parent = root
    crystal.scale = (0.04, 0.04, 0.12)
    crystal.location = (math.cos(angle) * 0.94, math.sin(angle) * 0.94, 0.07)
    crystals.append((crystal, angle))
    # Tiny radial glyphs leave the middle open, so the chess piece stays visible.
    arc("Radial rune", 1.18, angle - 0.035, 0.07, 0.012, 0, light_material)

bpy.ops.object.camera_add(location=(0, -3.8, 6.5))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0.03)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 3.15
scene.camera = camera
bpy.ops.object.light_add(type="AREA", location=(-2, -3, 5))
bpy.context.object.data.energy = 350
bpy.context.object.data.size = 3

# Keep raw RGBA geometry. Optical bloom is composited in ImageMagick so
# transparent falloff stays explicit and independent of Blender node versions.

for frame in range(16):
    t = frame / 15
    root.rotation_euler.z = t * 0.55
    opening = 0.7 + 0.3 * (1 - (1 - t) ** 3)
    root.scale = (opening, opening, opening)
    for crystal, angle in crystals:
        crystal.location.z = 0.08 + 0.04 * math.sin(t * math.pi + angle)
        crystal.rotation_euler.z = angle + t * math.pi * 0.6
    scene.render.filepath = str(out / f"halo-{frame:02d}.png")
    bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out.parent / "arcane-halo.blend"))
