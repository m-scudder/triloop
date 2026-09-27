#!/usr/bin/env python3
"""Install downloaded MakeHuman/MPFB asset packs into MPFB user data.

Run inside Blender after MPFB is installed/enabled:
blender -b --python install_asset_packs.py -- --pack a.zip --pack b.zip
"""

import argparse
import importlib
import os
import sys
import zipfile


def args_after_double_dash():
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", action="append", required=True)
    return parser.parse_args(args_after_double_dash())


def dynamic_import(package_suffix, key):
    for module_name in list(sys.modules):
        if module_name.endswith(package_suffix):
            module = importlib.import_module(module_name)
            if hasattr(module, key):
                return getattr(module, key)
    raise RuntimeError(
        "MPFB is not loaded. Install and enable the MPFB extension first."
    )


def main():
    args = parse_args()

    LocationService = dynamic_import(
        "mpfb.services.locationservice",
        "LocationService",
    )
    AssetService = dynamic_import(
        "mpfb.services.assetservice",
        "AssetService",
    )

    destination = LocationService.get_user_data()
    os.makedirs(destination, exist_ok=True)

    for pack in args.pack:
        path = os.path.abspath(pack)
        if not zipfile.is_zipfile(path):
            raise RuntimeError("Not a valid asset-pack ZIP: " + path)

        print("Installing asset pack:", path)
        with zipfile.ZipFile(path, "r") as archive:
            archive.extractall(destination)

    AssetService.update_all_asset_lists()

    print("Installed", len(args.pack), "asset pack(s)")
    print("MPFB user data:", destination)


if __name__ == "__main__":
    main()
