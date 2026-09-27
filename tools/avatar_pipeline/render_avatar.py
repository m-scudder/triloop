#!/usr/bin/env python3
"""Render one Athevia avatar configuration inside Blender.

Run through Blender:
blender -b master.blend --python render_avatar.py -- \
  --config render.json \
  --catalog catalog.json \
  --output out.png
"""

import argparse
import json
import os
import sys

import bpy


def args_after_double_dash():
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args(args_after_double_dash())


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def require_object(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError("Required Blender object is missing: " + name)
    return obj


def require_material(name):
    material = bpy.data.materials.get(name)
    if material is None:
        raise RuntimeError("Required Blender material is missing: " + name)
    return material


def set_visible(obj, visible):
    obj.hide_viewport = not visible
    obj.hide_render = not visible


def hex_to_rgba(value):
    value = value.lstrip("#")
    if len(value) != 6:
        raise ValueError("Expected six-digit hex color, got: " + value)
    return tuple(int(value[index:index + 2], 16) / 255.0 for index in (0, 2, 4)) + (1.0,)


def set_principled_base_color(material_name, hex_color):
    material = require_material(material_name)
    if not material.use_nodes:
        material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    if node is None:
        raise RuntimeError("Material has no Principled BSDF: " + material_name)
    node.inputs["Base Color"].default_value = hex_to_rgba(hex_color)


def set_shape_key(body, key_name, value):
    keys = getattr(getattr(body.data, "shape_keys", None), "key_blocks", None)
    if keys is None:
        if value != 0:
            raise RuntimeError("Body has no shape keys but requested " + key_name)
        return
    key = keys.get(key_name)
    if key is None:
        if value != 0:
            raise RuntimeError("Missing body shape key: " + key_name)
        return
    key.value = value


def hide_prefixed(prefix):
    for obj in bpy.data.objects:
        if obj.name.startswith(prefix):
            set_visible(obj, False)


def configure_body(config, catalog):
    presentation = config["appearance"]["presentation"]
    body = require_object("BODY__" + presentation)

    for candidate in ("BODY__feminine", "BODY__masculine"):
        obj = bpy.data.objects.get(candidate)
        if obj is not None:
            set_visible(obj, obj == body)

    preset = catalog["bodies"][config["appearance"]["bodyPreset"]]
    set_shape_key(body, "BODY__lean", float(preset["leanShape"]))
    set_shape_key(body, "BODY__powerful", float(preset["powerfulShape"]))

    set_principled_base_color(
        "MAT__skin",
        catalog["skinTones"][config["appearance"]["skinTone"]],
    )


def configure_hair(config, catalog):
    hide_prefixed("HAIR__")
    hair_id = config["appearance"]["hairStyle"]
    definition = catalog["hair"][hair_id]
    hair = require_object(definition["object"])
    set_visible(hair, True)
    set_principled_base_color(
        definition["material"],
        catalog["hairColors"][config["appearance"]["hairColor"]],
    )


def configure_gear(config, catalog):
    hide_prefixed("GEAR__")
    loadout = config["loadout"]

    for slot in ("top", "bottom", "footwear", "headwear", "accessory"):
        gear_id = loadout.get(slot)
        if gear_id is None:
            continue

        definition = catalog["gear"].get(gear_id)
        if definition is None:
            raise RuntimeError("Gear is not in avatar catalog: " + gear_id)

        obj = require_object(definition["object"])
        set_visible(obj, True)

        material_name = definition.get("material")
        color = definition.get("color")
        if material_name and color:
            set_principled_base_color(material_name, color)


def configure_pose(config, catalog):
    rig = require_object(catalog["render"]["rig"])
    pose_name = config["pose"]
    action = bpy.data.actions.get("POSE__" + pose_name)
    if action is None:
        raise RuntimeError("Missing pose action: POSE__" + pose_name)

    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = action
    bpy.context.scene.frame_set(1)


def configure_render(config, catalog, output):
    scene = bpy.context.scene
    render = catalog["render"]

    camera = require_object(render["camera"])
    scene.camera = camera

    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = int(render["width"])
    scene.render.resolution_y = int(render["height"])
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True

    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = os.path.abspath(output)

    # Stable color handling matters more than artistic variation.
    scene.view_settings.look = "Medium High Contrast"

    bpy.ops.render.render(write_still=True)


def main():
    args = parse_args()
    config = load_json(args.config)
    catalog = load_json(args.catalog)

    configure_body(config, catalog)
    configure_hair(config, catalog)
    configure_gear(config, catalog)
    configure_pose(config, catalog)
    configure_render(config, catalog, args.output)


if __name__ == "__main__":
    main()
