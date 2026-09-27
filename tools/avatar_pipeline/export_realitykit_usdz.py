#!/usr/bin/env python3
"""Export the generated Athevia master athlete as a RealityKit-ready USDZ.

Run inside Blender:
blender -b master.blend --python export_realitykit_usdz.py -- \
  --output AtheviaAthleteFeminine.usdz

The export preserves:
- USD skeleton / skinning
- three discrete skinned body presets
- named mesh hierarchy used by the iOS runtime
- USD Preview Surface materials

The file is intentionally a single modular character package. RealityKit changes
mesh visibility, materials and body blend-shape weights at runtime.
"""

import argparse
import os
import sys

import bpy


def args_after_double_dash():
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    return parser.parse_args(args_after_double_dash())


def make_runtime_assets_visible():
    """USD doesn't export hidden meshes reliably; export all runtime parts."""
    runtime_prefixes = (
        "BODY__",
        "FACE__",
        "HAIR__",
        "GEAR__",
        "RIG__",
    )

    for obj in bpy.data.objects:
        if obj.name.startswith(runtime_prefixes):
            obj.hide_viewport = False
            obj.hide_render = False

    # Authoring-only camera/light objects are not needed in the iOS package.
    for obj in bpy.data.objects:
        if obj.type in {"LIGHT", "CAMERA"}:
            obj.hide_viewport = True
            obj.hide_render = True


def validate_required_hierarchy():
    required = (
        "RIG__athlete",
        "HAIR__tied",
        "GEAR__runTopPerformance",
        "GEAR__runShort",
        "GEAR__runShoe",
    )

    missing = [name for name in required if bpy.data.objects.get(name) is None]

    if not any(obj.name.startswith("BODY__") for obj in bpy.data.objects):
        missing.append("BODY__*")

    if missing:
        raise RuntimeError(
            "Master scene does not satisfy RealityKit export contract: "
            + ", ".join(missing)
        )


def main():
    args = parse_args()
    output = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(output), exist_ok=True)

    if not output.lower().endswith(".usdz"):
        raise RuntimeError("RealityKit export must use the .usdz extension")

    validate_required_hierarchy()
    make_runtime_assets_visible()

    scene = bpy.context.scene
    scene.frame_set(1)

    # Keep the saved source actions in the .blend source of truth. Runtime poses
    # are driven through RealityKit's skeleton APIs, so the USDZ only needs the
    # rest skeleton, skinning and blend-shape data.
    rig = bpy.data.objects.get("RIG__athlete")
    if rig is not None and rig.animation_data is not None:
        rig.animation_data.action = None

    result = bpy.ops.wm.usd_export(
        filepath=output,
        selected_objects_only=False,
        export_animation=False,
        export_uvmaps=True,
        rename_uvmaps=True,
        export_mesh_colors=True,
        export_normals=True,
        export_materials=True,
        export_armatures=True,
        only_deform_bones=False,
        export_shapekeys=False,
        use_instancing=False,
        evaluation_mode="RENDER",
        generate_preview_surface=True,
        relative_paths=True,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        export_textures_mode="NEW",
        overwrite_textures=True,
        xform_op_mode="TRS",
        root_prim_path="/AtheviaAthlete",
        export_custom_properties=True,
        convert_scene_units="METERS",
        meters_per_unit=1.0,
        export_lights=False,
        export_cameras=False,
    )

    if "FINISHED" not in result:
        raise RuntimeError("Blender USDZ export did not finish: " + str(result))

    if not os.path.isfile(output) or os.path.getsize(output) == 0:
        raise RuntimeError("USDZ export produced no output: " + output)

    print("RealityKit USDZ:", output)
    print("Size bytes:", os.path.getsize(output))


if __name__ == "__main__":
    main()
