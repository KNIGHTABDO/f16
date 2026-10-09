#!/usr/bin/env python3
"""
render_aircraft.py - Renders sleek 3-quarter front profile renders of aircraft 3D models using Blender.
Outputs 1024x512 transparent PNGs with cinematic rim & key lighting.
"""

import math
import os
import sys

try:
    import bpy
    import mathutils
except ImportError:
    pass

def render_aircraft_model(glb_path, output_png):
    os.makedirs(os.path.dirname(os.path.abspath(output_png)), exist_ok=True)
    
    # Reset scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # Import GLB
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    # Hide gear / landing gear parts for sleek in-flight render
    for obj in bpy.context.scene.objects:
        if any(k in obj.name.lower() for k in ['gear', 'wheel', 'strut', 'tire', 'door']):
            # Keep airframe doors if they aren't gear doors
            if 'gear' in obj.name.lower() or 'wheel' in obj.name.lower() or 'strut' in obj.name.lower() or 'tire' in obj.name.lower():
                obj.hide_render = True
                obj.hide_viewport = True

    # Collect visible mesh objects
    mesh_objs = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH' and not obj.hide_render]
    if not mesh_objs:
        mesh_objs = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']

    # Calculate overall bounding box of visible meshes
    min_co = [float('inf')] * 3
    max_co = [float('-inf')] * 3
    
    for obj in mesh_objs:
        mat = obj.matrix_world
        for corner in obj.bound_box:
            world_corner = mat @ mathutils.Vector(corner)
            for i in range(3):
                min_co[i] = min(min_co[i], world_corner[i])
                max_co[i] = max(max_co[i], world_corner[i])
                
    center = mathutils.Vector([(min_co[i] + max_co[i]) / 2 for i in range(3)])
    dimensions = mathutils.Vector([max_co[i] - min_co[i] for i in range(3)])
    max_dim = max(dimensions.x, dimensions.y, dimensions.z)
    
    # Center all objects
    for obj in bpy.context.scene.objects:
        if obj.parent is None:
            obj.location -= center

    # Setup Camera for 3-quarter front view
    cam_data = bpy.data.cameras.new("RenderCam")
    cam_data.lens = 72
    cam_obj = bpy.data.objects.new("RenderCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    # Camera looking from front-left (nose +Y, right wing +X, top +Z)
    dist = max_dim * 2.05
    yaw = math.radians(62)   # 62 degrees from nose towards side
    pitch = math.radians(15)  # 15 degrees elevation
    
    cam_x = -dist * math.cos(pitch) * math.sin(yaw)
    cam_y = dist * math.cos(pitch) * math.cos(yaw)
    cam_z = dist * math.sin(pitch)
    
    cam_obj.location = mathutils.Vector((cam_x, cam_y, cam_z))
    direction = -cam_obj.location
    rot_quat = direction.to_track_quat('-Z', 'Y')
    cam_obj.rotation_euler = rot_quat.to_euler()

    # Lighting setup
    # Key light: Warm amber sun
    key_light_data = bpy.data.lights.new(name="KeyLight", type='SUN')
    key_light_data.energy = 5.0
    key_light_data.color = (1.0, 0.92, 0.8)
    key_light_obj = bpy.data.objects.new(name="KeyLight", object_data=key_light_data)
    key_light_obj.rotation_euler = (math.radians(40), math.radians(-25), math.radians(45))
    scene.collection.objects.link(key_light_obj)

    # Fill light: Cool navy sky fill
    fill_light_data = bpy.data.lights.new(name="FillLight", type='SUN')
    fill_light_data.energy = 2.5
    fill_light_data.color = (0.4, 0.65, 0.95)
    fill_light_obj = bpy.data.objects.new(name="FillLight", object_data=fill_light_data)
    fill_light_obj.rotation_euler = (math.radians(-35), math.radians(40), math.radians(-120))
    scene.collection.objects.link(fill_light_obj)

    # Rim light: Vivid cyan accent rim light from rear-right
    rim_light_data = bpy.data.lights.new(name="RimLight", type='SUN')
    rim_light_data.energy = 4.0
    rim_light_data.color = (0.25, 0.82, 1.0)
    rim_light_obj = bpy.data.objects.new(name="RimLight", object_data=rim_light_data)
    rim_light_obj.rotation_euler = (math.radians(-50), math.radians(-30), math.radians(-160))
    scene.collection.objects.link(rim_light_obj)

    # Render settings
    scene.render.engine = 'BLENDER_EEVEE'
    scene.eevee.taa_render_samples = 16  # Fast clean render
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 512
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = output_png

    bpy.ops.render.render(write_still=True)
    print(f"Successfully rendered {glb_path} -> {output_png}")
    return True

if __name__ == "__main__":
    argv = sys.argv
    if "--" in argv:
        args = argv[argv.index("--") + 1:]
        if len(args) >= 2:
            render_aircraft_model(args[0], args[1])
        elif len(args) == 1 and args[0] == "all":
            aircraft_list = ["f16c", "ef2000", "f35a", "su27", "mig29", "f15c", "mig21bis"]
            for ac_id in aircraft_list:
                glb = f"game/assets/models/aircraft/{ac_id}/{ac_id}.glb"
                out = f"game/assets/ui/aircraft/{ac_id}.png"
                if os.path.exists(glb):
                    render_aircraft_model(glb, out)
