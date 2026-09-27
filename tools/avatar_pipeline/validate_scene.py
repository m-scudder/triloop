#!/usr/bin/env python3
"""Validate that a Blender master scene satisfies the Athevia avatar contract."""

import argparse
import json
import sys

import bpy


def args_after_double_dash():
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--poses", required=True)
    return parser.parse_args(args_after_double_dash())


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def main():
    args = parse_args()
    catalog = load_json(args.catalog)
    poses = load_json(args.poses)

    missing = []

    base_body_name = (
        "BODY__feminine"
        if bpy.data.objects.get("BODY__feminine") is not None
        else "BODY__masculine"
    )

    required_objects = [
        catalog["render"]["camera"],
        catalog["render"]["rig"],
        base_body_name,
        "BODY__lean",
        "BODY__powerful",
        "HAIR__tied",
    ]

    for definition in catalog["gear"].values():
        required_objects.append(definition["object"])

    for name in sorted(set(required_objects)):
        if bpy.data.objects.get(name) is None:
            missing.append("object:" + name)

    required_materials = ["MAT__skin"]
    for definition in catalog["gear"].values():
        material = definition.get("material")
        if material:
            required_materials.append(material)

    for name in sorted(set(required_materials)):
        if bpy.data.materials.get(name) is None:
            missing.append("material:" + name)

    body_names = [base_body_name, "BODY__lean", "BODY__powerful"]
    body_objects = [
        bpy.data.objects.get(name)
        for name in body_names
        if bpy.data.objects.get(name) is not None
    ]

    if len(body_objects) == 3:
        vertex_counts = {len(body.data.vertices) for body in body_objects}
        if len(vertex_counts) != 1:
            missing.append("bodyPresetTopologyMismatch")

        rig = bpy.data.objects.get(catalog["render"]["rig"])
        for body in body_objects:
            keys = getattr(getattr(body.data, "shape_keys", None), "key_blocks", None)
            if keys is not None and len(keys) > 0:
                missing.append("unexpectedShapeKeys:" + body.name)

            armatures = [
                modifier for modifier in body.modifiers
                if modifier.type == "ARMATURE"
            ]
            if not armatures or armatures[-1].object != rig:
                missing.append("sharedRigBinding:" + body.name)

    for pose_name in poses:
        if bpy.data.actions.get("POSE__" + pose_name) is None:
            missing.append("action:POSE__" + pose_name)

    if missing:
        print("Athevia avatar scene validation failed:")
        for item in missing:
            print(" -", item)
        raise SystemExit(1)

    print("Athevia avatar scene validation passed.")
    print("Objects:", len(set(required_objects)))
    print("Materials:", len(set(required_materials)))
    print("Poses:", len(poses))


if __name__ == "__main__":
    main()
