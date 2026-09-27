#!/usr/bin/env python3
"""Package deterministic avatar PNG renders into Xcode .imageset folders."""

import argparse
import json
import os
import shutil


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--renders", required=True)
    parser.add_argument("--asset-catalog", required=True)
    return parser.parse_args()


def contents_json(filename):
    return {
        "images": [
            {
                "filename": filename,
                "idiom": "universal",
                "scale": "1x",
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }


def main():
    args = parse_args()

    if not os.path.isdir(args.renders):
        raise SystemExit("Render directory does not exist: " + args.renders)
    if not os.path.isdir(args.asset_catalog):
        raise SystemExit("Asset catalog does not exist: " + args.asset_catalog)

    pngs = sorted(
        entry
        for entry in os.listdir(args.renders)
        if entry.startswith("AvatarRender__") and entry.endswith(".png")
    )

    if not pngs:
        raise SystemExit("No AvatarRender PNGs found in " + args.renders)

    for filename in pngs:
        asset_name = filename[:-4]
        imageset = os.path.join(args.asset_catalog, asset_name + ".imageset")
        os.makedirs(imageset, exist_ok=True)

        destination = os.path.join(imageset, filename)
        shutil.copy2(os.path.join(args.renders, filename), destination)

        with open(
            os.path.join(imageset, "Contents.json"),
            "w",
            encoding="utf-8",
        ) as handle:
            json.dump(contents_json(filename), handle, indent=2)
            handle.write("\n")

        print("Updated", imageset)


if __name__ == "__main__":
    main()
