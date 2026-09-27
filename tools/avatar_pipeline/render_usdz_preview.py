#!/usr/bin/env python3
"""Render a sanity-check preview from an exported Athevia USDZ package."""

import argparse
import os
import sys

import bpy
from mathutils import Vector


def args_after_double_dash():
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--usdz", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args(args_after_double_dash())


def descendants(root):
    result = [root]
    for child in root.children:
        result.extend(descendants(child))
    return result


def look_at(obj, point):
    direction = Vector(point) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def visible_runtime_selection():
    for obj in bpy.data.objects:
        if obj.name.startswith("HAIR__"):
            obj.hide_render = obj.name != "HAIR__tied"
            obj.hide_viewport = obj.hide_render

        if obj.name.startswith("GEAR__"):
            enabled = obj.name in {
                "GEAR__runTopPerformance",
                "GEAR__runShort",
                "GEAR__runShoe",
            }
            obj.hide_render = not enabled
            obj.hide_viewport = not enabled


def validate_dimensions():
    bodies = [obj for obj in bpy.data.objects if obj.name.startswith("BODY__")]
    if not bodies:
        raise RuntimeError("USDZ round-trip has no BODY__ mesh")

    body = bodies[0]
    dims = body.dimensions
    print("Round-trip body dimensions:", tuple(float(v) for v in dims))

    # MakeHuman runtime athlete is roughly 1.5–2.1m tall. Allow generous bounds
    # while catching the catastrophic body explosion seen on-device.
    ordered = sorted(float(v) for v in dims)
    height = ordered[-1]
    width = ordered[-2]

    if not (1.2 <= height <= 2.6):
        raise RuntimeError("USDZ body height outside sane bounds: " + str(height))

    if width > 1.6:
        raise RuntimeError("USDZ body width outside sane bounds: " + str(width))

    keys = getattr(getattr(body.data, "shape_keys", None), "key_blocks", None)
    if keys is not None:
        names = [key.name for key in keys]
        print("Round-trip body shape keys:", names)
        unexpected = [
            name for name in names
            if name not in {"Basis", "BODY__lean", "BODY__powerful"}
        ]
        if unexpected:
            raise RuntimeError(
                "USDZ contains unexpected authoring morphs: " + ", ".join(unexpected)
            )


def add_camera_and_lights():
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0.0, -4.7, 1.05)
    camera.data.lens = 58
    look_at(camera, (0.0, 0.0, 0.95))
    bpy.context.scene.camera = camera

    def area(name, location, energy, size):
        data = bpy.data.lights.new(name=name, type="AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        obj.location = location
        look_at(obj, (0.0, 0.0, 1.0))

    area("Key", (-2.1, -2.4, 2.8), 1000, 2.4)
    area("Fill", (2.2, -1.8, 2.0), 500, 2.8)
    area("Rim", (0.6, 1.8, 2.6), 700, 2.0)


def main():
    args = parse_args()
    usdz = os.path.abspath(args.usdz)
    output = os.path.abspath(args.output)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    result = bpy.ops.wm.usd_import(filepath=usdz)
    if "FINISHED" not in result:
        raise RuntimeError("Blender could not import USDZ: " + str(result))

    visible_runtime_selection()
    validate_dimensions()
    add_camera_and_lights()

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.world.color = (0.025, 0.03, 0.04)
    scene.render.filepath = output

    bpy.ops.render.render(write_still=True)

    if not os.path.isfile(output) or os.path.getsize(output) == 0:
        raise RuntimeError("USDZ preview render was not created")

    print("USDZ preview:", output)


if __name__ == "__main__":
    main()
