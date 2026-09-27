#!/usr/bin/env python3
"""Validate Athevia avatar-pipeline configuration without requiring Blender."""

import argparse
import json
import os
import re
import sys


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_swift_gear_ids(path):
    text = open(path, "r", encoding="utf-8").read()
    match = re.search(
        r"enum\s+AvatarGearID[^\{]*\{(?P<body>.*?)\n\}",
        text,
        flags=re.DOTALL,
    )
    if not match:
        raise RuntimeError("Could not locate AvatarGearID enum")

    ids = set()
    for line in match.group("body").splitlines():
        line = line.strip()
        if not line.startswith("case "):
            continue
        payload = line[len("case "):].split("//", 1)[0]
        for item in payload.split(","):
            name = item.strip().split("=", 1)[0].strip()
            if name:
                ids.add(name)
    return ids


def canonical_name(appearance, sport, loadout, pose):
    def value_or_none(value):
        return value if value is not None else "none"

    return "__".join([
        "AvatarRender",
        appearance["presentation"],
        appearance["bodyPreset"],
        appearance["skinTone"],
        appearance["hairStyle"],
        appearance["hairColor"],
        sport,
        loadout["top"],
        loadout["bottom"],
        loadout["footwear"],
        value_or_none(loadout.get("headwear")),
        value_or_none(loadout.get("accessory")),
        pose,
    ])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--matrix", required=True)
    parser.add_argument("--poses", required=True)
    parser.add_argument("--swift-avatar", required=True)
    args = parser.parse_args()

    catalog = load_json(args.catalog)
    matrix = load_json(args.matrix)
    poses = load_json(args.poses)
    swift_ids = parse_swift_gear_ids(args.swift_avatar)

    errors = []

    required_appearance = {
        "presentation",
        "skinTone",
        "bodyPreset",
        "hairStyle",
        "hairColor",
    }
    missing_appearance = required_appearance - set(matrix["appearance"])
    if missing_appearance:
        errors.append(
            "matrix appearance missing: " + ", ".join(sorted(missing_appearance))
        )

    for pose in matrix["poses"]:
        if pose not in poses:
            errors.append("matrix references undefined pose: " + pose)

    all_assets = []
    for variant in matrix["variants"]:
        loadout = variant["loadout"]
        for slot in ("top", "bottom", "footwear", "headwear", "accessory"):
            gear_id = loadout.get(slot)
            if gear_id is None:
                continue

            if gear_id not in swift_ids:
                errors.append(
                    variant["name"] + " references gear not present in Swift: " + gear_id
                )
            if gear_id not in catalog["gear"]:
                errors.append(
                    variant["name"] + " references gear not present in catalog: " + gear_id
                )

        for pose in matrix["poses"]:
            all_assets.append(
                canonical_name(
                    matrix["appearance"],
                    matrix["sport"],
                    loadout,
                    pose,
                )
            )

    for gear_id in catalog["gear"]:
        if gear_id not in swift_ids:
            errors.append("catalog gear not present in Swift: " + gear_id)

    body = matrix["appearance"]["bodyPreset"]
    skin = matrix["appearance"]["skinTone"]
    hair = matrix["appearance"]["hairStyle"]
    hair_color = matrix["appearance"]["hairColor"]

    if body not in catalog["bodies"]:
        errors.append("body preset missing from catalog: " + body)
    if skin not in catalog["skinTones"]:
        errors.append("skin tone missing from catalog: " + skin)
    if hair not in catalog["hair"]:
        errors.append("hair style missing from catalog: " + hair)
    if hair_color not in catalog["hairColors"]:
        errors.append("hair color missing from catalog: " + hair_color)

    duplicates = sorted(
        name for name in set(all_assets)
        if all_assets.count(name) > 1
    )
    if duplicates:
        errors.append("duplicate render asset names: " + ", ".join(duplicates))

    if errors:
        print("Avatar pipeline configuration validation failed:")
        for error in errors:
            print(" -", error)
        raise SystemExit(1)

    print("Avatar pipeline configuration is valid.")
    print("Swift gear IDs:", len(swift_ids))
    print("Catalog gear definitions:", len(catalog["gear"]))
    print("Configured poses:", len(poses))
    print("Vertical-slice renders:", len(all_assets))
    for name in all_assets:
        print(" -", name)


if __name__ == "__main__":
    main()
