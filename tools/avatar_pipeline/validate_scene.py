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

    required_objects = [
        catalog["render"]["camera"],
        catalog["render"]["rig"],
        "BODY__feminine",
        "HAIR__tied",
    ]

    for definition in catalog["gear"].values():
        required_objects.append(definition["object"])

    for name in sorted(set(required_objects)):
        if bpy.data.objects.get(name) is None:
            missing.append("object:" + name)

    required_materials = ["MAT__skin", "MAT__hair"]
    for definition in catalog["gear"].values():
        material = definition.get("material")
        if material:
            required_materials.append(material)

    for name in sorted(set(required_materials)):
        if bpy.data.materials.get(name) is None:
            missing.append("material:" + name)

    body = bpy.data.objects.get("BODY__feminine") or bpy.data.objects.get("BODY__masculine")
    if body is not None:
        keys = getattr(getattr(body.data, "shape_keys", None), "key_blocks", None)
        expected = ["Basis", "BODY__lean", "BODY__powerful"]
        if keys is None:
            missing.append("shapeKeys:" + ",".join(expected))
        else:
            actual = [key.name for key in keys]
            if actual != expected:
                missing.append(
                    "shapeKeyContract:expected="
                    + ",".join(expected)
                    + ";actual="
                    + ",".join(actual)
                )

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
