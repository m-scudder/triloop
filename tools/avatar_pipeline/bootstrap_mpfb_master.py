#!/usr/bin/env python3
"""Create the first Athevia master athlete from the free MPFB Blender extension.

This script is intended to run inside Blender after MPFB is installed/enabled:

blender -b --python bootstrap_mpfb_master.py -- \
  --output /path/to/athevia-athlete-master.blend \
  --presentation feminine \
  --poses config/poses.json

It creates:
- a reusable MPFB body with lean / powerful morph targets
- a game-engine rig with stable bone names
- automatically selected hair / top / shorts / shoes from installed MPFB assets
- fixed camera and studio light rig
- data-driven pose actions
"""

import argparse
import importlib
import json
import math
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
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--presentation",
        choices=("feminine", "masculine"),
        default="feminine",
    )
    parser.add_argument("--poses", required=True)
    parser.add_argument("--hair-keywords", default="bun,ponytail,updo,tied")
    parser.add_argument("--top-keywords", default="tank,sport,top,shirt")
    parser.add_argument("--bottom-keywords", default="jeans_shorts,shorts,short")
    parser.add_argument("--shoe-keywords", default="shoes01")
    return parser.parse_args(args_after_double_dash())


def dynamic_import(package_suffix, key):
    for module_name in list(sys.modules):
        if module_name.endswith(package_suffix):
            module = importlib.import_module(module_name)
            if hasattr(module, key):
                return getattr(module, key)
    raise RuntimeError(
        "MPFB is not loaded. Install and enable the MPFB Blender extension "
        "before running this script. Missing: " + package_suffix + "." + key
    )


def macro_details(TargetService, presentation, body_preset):
    macro = TargetService.get_default_macro_info_dict()

    macro["gender"] = 1.0 if presentation == "feminine" else 0.0
    macro["age"] = 0.36
    macro["height"] = 0.52
    macro["proportions"] = 0.50

    if body_preset == "lean":
        macro["muscle"] = 0.56
        macro["weight"] = 0.34
    elif body_preset == "powerful":
        macro["muscle"] = 0.82
        macro["weight"] = 0.58
    else:
        macro["muscle"] = 0.68
        macro["weight"] = 0.44

    return macro


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def add_variant_shape(base, variant, key_name):
    if base.data.shape_keys is None:
        base.shape_key_add(name="Basis")

    before = len(base.data.shape_keys.key_blocks)
    bpy.ops.object.select_all(action="DESELECT")
    variant.select_set(True)
    base.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join_shapes()

    keys = base.data.shape_keys.key_blocks
    if len(keys) <= before:
        raise RuntimeError("Blender did not create shape key " + key_name)
    keys[-1].name = key_name
    keys[-1].value = 0.0


def normalize_material_name(obj, desired_name):
    if not hasattr(obj.data, "materials"):
        return None

    if obj.data.materials:
        material = obj.data.materials[0]
    else:
        material = bpy.data.materials.new(desired_name)
        material.use_nodes = True
        obj.data.materials.append(material)

    material.name = desired_name
    if not material.use_nodes:
        material.use_nodes = True
    return material


def find_asset(AssetService, subdir, keywords, used_paths):
    AssetService.update_asset_list(asset_subdir=subdir, asset_type="mhclo")
    assets = AssetService.get_asset_list(subdir, "mhclo")
    if not assets:
        raise RuntimeError(
            "No MPFB assets found in '" + subdir + "'. "
            "Install the free MPFB system assets pack first."
        )

    keyword_list = [
        token.strip().lower()
        for token in keywords.split(",")
        if token.strip()
    ]

    candidates = []
    for label, info in assets.items():
        path = info["full_path"]
        if path in used_paths:
            continue
        haystack = (str(label) + " " + str(info.get("basename", ""))).lower()
        score = 0
        for index, keyword in enumerate(keyword_list):
            if keyword in haystack:
                score += max(1, 100 - index * 10)
        candidates.append((score, str(label), info))

    candidates.sort(key=lambda item: (-item[0], item[1].lower()))
    if not candidates or candidates[0][0] == 0:
        preview = ", ".join(item[1] for item in candidates[:20])
        raise RuntimeError(
            "Could not automatically select a suitable " + subdir +
            " asset for keywords " + str(keyword_list) +
            ". Available examples: " + preview
        )

    return candidates[0][2]


def add_asset(HumanService, basemesh, definition, asset_type, object_name, material_name):
    obj = HumanService.add_mhclo_asset(
        definition["full_path"],
        basemesh,
        asset_type=asset_type,
        subdiv_levels=1,
        material_type="MAKESKIN",
        set_up_rigging=True,
        interpolate_weights=True,
        import_subrig=True,
        import_weights=True,
    )
    if obj is None:
        raise RuntimeError("Failed to load MPFB asset: " + definition["full_path"])
    obj.name = object_name
    normalize_material_name(obj, material_name)
    return obj


def look_at(obj, point):
    direction = Vector(point) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def create_camera_and_lighting():
    for obj in list(bpy.data.objects):
        if obj.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(obj, do_unlink=True)

    camera_data = bpy.data.cameras.new("CAMERA__avatar")
    camera = bpy.data.objects.new("CAMERA__avatar", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0.0, -4.7, 1.05)
    camera.data.lens = 58
    look_at(camera, (0.0, 0.0, 0.95))

    def area(name, location, energy, size, color):
        data = bpy.data.lights.new(name=name, type="AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        obj.location = location
        look_at(obj, (0.0, 0.0, 1.0))
        return obj

    area(
        "LIGHT__key",
        (-2.1, -2.4, 2.8),
        1050,
        2.4,
        (1.0, 0.82, 0.72),
    )
    area(
        "LIGHT__fill",
        (2.2, -1.8, 2.0),
        650,
        2.8,
        (0.72, 0.82, 1.0),
    )
    area(
        "LIGHT__rim",
        (0.6, 1.8, 2.6),
        850,
        2.0,
        (1.0, 0.72, 0.58),
    )

    bpy.context.scene.camera = camera
    bpy.context.scene.render.film_transparent = True


def reset_pose(rig):
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def create_pose_action(rig, pose_name, degrees_by_bone):
    reset_pose(rig)

    for bone_name, degrees in degrees_by_bone.items():
        bone = rig.pose.bones.get(bone_name)
        if bone is None:
            print("Warning: pose bone not found:", bone_name)
            continue
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = tuple(
            math.radians(float(component))
            for component in degrees
        )

    action = bpy.data.actions.new("POSE__" + pose_name)
    # These actions are intentionally not attached to the rig in the saved neutral
    # state, so fake-user persistence prevents Blender from pruning them on save.
    action.use_fake_user = True

    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = action

    for bone in rig.pose.bones:
        bone.keyframe_insert(data_path="rotation_euler", frame=1)
        bone.keyframe_insert(data_path="location", frame=1)
        bone.keyframe_insert(data_path="scale", frame=1)

    rig.animation_data.action = None
    reset_pose(rig)


def main():
    args = parse_args()

    HumanService = dynamic_import(
        "mpfb.services.humanservice",
        "HumanService",
    )
    TargetService = dynamic_import(
        "mpfb.services.targetservice",
        "TargetService",
    )
    AssetService = dynamic_import(
        "mpfb.services.assetservice",
        "AssetService",
    )

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    balanced = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=macro_details(
            TargetService,
            args.presentation,
            "balanced",
        ),
    )
    balanced.name = "BODY__" + args.presentation

    lean = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=macro_details(
            TargetService,
            args.presentation,
            "lean",
        ),
    )
    powerful = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=macro_details(
            TargetService,
            args.presentation,
            "powerful",
        ),
    )

    activate(balanced)
    add_variant_shape(balanced, lean, "BODY__lean")
    add_variant_shape(balanced, powerful, "BODY__powerful")

    bpy.data.objects.remove(lean, do_unlink=True)
    bpy.data.objects.remove(powerful, do_unlink=True)

    normalize_material_name(balanced, "MAT__skin")

    rig = HumanService.add_builtin_rig(
        balanced,
        "game_engine",
        import_weights=True,
    )
    if rig is None:
        raise RuntimeError("MPFB did not create the game_engine rig")
    rig.name = "RIG__athlete"

    used = set()

    # Facial components are loaded from the CC0 MakeHuman system assets pack.
    # This avoids a technically correct but visibly unfinished basemesh face.
    facial_assets = [
        ("eyes", "high-poly", "Eyes", "FACE__eyes", "MAT__eyes"),
        ("eyebrows", "eyebrow", "Eyebrows", "FACE__eyebrows", "MAT__eyebrows"),
        ("eyelashes", "eyelashes", "Eyelashes", "FACE__eyelashes", "MAT__eyelashes"),
        ("teeth", "teeth_base", "Teeth", "FACE__teeth", "MAT__teeth"),
    ]

    for subdir, keywords, asset_type, object_name, material_name in facial_assets:
        definition = find_asset(
            AssetService,
            subdir,
            keywords,
            used,
        )
        used.add(definition["full_path"])
        add_asset(
            HumanService,
            balanced,
            definition,
            asset_type,
            object_name,
            material_name,
        )

    hair_definition = find_asset(
        AssetService,
        "hair",
        args.hair_keywords,
        used,
    )
    used.add(hair_definition["full_path"])
    add_asset(
        HumanService,
        balanced,
        hair_definition,
        "hair",
        "HAIR__tied",
        "MAT__hair",
    )

    top_definition = find_asset(
        AssetService,
        "clothes",
        args.top_keywords,
        used,
    )
    used.add(top_definition["full_path"])
    add_asset(
        HumanService,
        balanced,
        top_definition,
        "Clothes",
        "GEAR__runTopPerformance",
        "MAT__runTopPerformance",
    )

    bottom_definition = find_asset(
        AssetService,
        "clothes",
        args.bottom_keywords,
        used,
    )
    used.add(bottom_definition["full_path"])
    add_asset(
        HumanService,
        balanced,
        bottom_definition,
        "Clothes",
        "GEAR__runShort",
        "MAT__runShort",
    )

    shoe_definition = find_asset(
        AssetService,
        "clothes",
        args.shoe_keywords,
        used,
    )
    used.add(shoe_definition["full_path"])
    add_asset(
        HumanService,
        balanced,
        shoe_definition,
        "Clothes",
        "GEAR__runShoe",
        "MAT__runShoe",
    )

    create_camera_and_lighting()

    with open(args.poses, "r", encoding="utf-8") as handle:
        pose_definitions = json.load(handle)

    for pose_name, definition in pose_definitions.items():
        create_pose_action(rig, pose_name, definition)

    # Keep the master in a predictable, neutral state.
    reset_pose(rig)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 2048
    scene.render.resolution_y = 2732
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True

    output = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(output), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=output)

    print("Saved Athevia master athlete:", output)
    print("Selected hair:", hair_definition["full_path"])
    print("Selected top:", top_definition["full_path"])
    print("Selected bottom:", bottom_definition["full_path"])
    print("Selected shoes:", shoe_definition["full_path"])


if __name__ == "__main__":
    main()
