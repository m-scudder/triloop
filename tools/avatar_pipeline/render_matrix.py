#!/usr/bin/env python3
"""Expand an Athevia avatar matrix and invoke Blender for every requested render."""

import argparse
import json
import os
import subprocess
import tempfile


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender", required=True)
    parser.add_argument("--master", required=True)
    parser.add_argument("--matrix", required=True)
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--render-scale", type=float, default=1.0)
    return parser.parse_args()


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def normalized(value):
    return value if value is not None else "none"


def asset_name(config):
    appearance = config["appearance"]
    loadout = config["loadout"]
    tokens = [
        "AvatarRender",
        appearance["presentation"],
        appearance["bodyPreset"],
        appearance["skinTone"],
        appearance["hairStyle"],
        appearance["hairColor"],
        config["sport"],
        loadout["top"],
        loadout["bottom"],
        loadout["footwear"],
        normalized(loadout.get("headwear")),
        normalized(loadout.get("accessory")),
        config["pose"],
    ]
    return "__".join(tokens)


def main():
    args = parse_args()
    matrix = load_json(args.matrix)
    os.makedirs(args.output, exist_ok=True)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    render_script = os.path.join(script_dir, "render_avatar.py")

    rendered = []
    for variant in matrix["variants"]:
        for pose in matrix["poses"]:
            config = {
                "appearance": matrix["appearance"],
                "sport": matrix["sport"],
                "loadout": variant["loadout"],
                "pose": pose,
            }

            name = asset_name(config)
            output = os.path.join(args.output, name + ".png")

            with tempfile.NamedTemporaryFile(
                mode="w",
                suffix=".json",
                delete=False,
                encoding="utf-8",
            ) as handle:
                json.dump(config, handle, indent=2)
                config_path = handle.name

            try:
                command = [
                    args.blender,
                    "-b",
                    args.master,
                    "--python-exit-code",
                    "1",
                    "--python",
                    render_script,
                    "--",
                    "--config",
                    config_path,
                    "--catalog",
                    args.catalog,
                    "--output",
                    output,
                    "--render-scale",
                    str(args.render_scale),
                ]
                print("Rendering:", name)
                subprocess.run(command, check=True)

                if not os.path.isfile(output) or os.path.getsize(output) == 0:
                    raise RuntimeError(
                        "Blender finished without producing render: " + output
                    )

                rendered.append(name)
            finally:
                os.unlink(config_path)

    manifest_path = os.path.join(args.output, "render-manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump({"assets": rendered}, handle, indent=2)

    print("Rendered", len(rendered), "avatar assets")
    print("Manifest:", manifest_path)


if __name__ == "__main__":
    main()
