#!/usr/bin/env python3
"""Inspect the prim hierarchy and skeleton bindings of an Athevia USDZ."""

import argparse
from pxr import Usd, UsdSkel


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--usdz", required=True)
    args = parser.parse_args()

    stage = Usd.Stage.Open(args.usdz)
    if stage is None:
        raise RuntimeError("Could not open USDZ: " + args.usdz)

    print("USDZ stage:", args.usdz)
    print("defaultPrim:", stage.GetDefaultPrim().GetPath())

    for prim in stage.Traverse():
        path = str(prim.GetPath())
        type_name = prim.GetTypeName()
        active = prim.IsActive()
        visibility = prim.GetAttribute("visibility").Get()
        print(
            "PRIM",
            path,
            "type=" + str(type_name),
            "active=" + str(active),
            "visibility=" + str(visibility),
        )

        if prim.IsA(UsdSkel.Skeleton):
            skeleton = UsdSkel.Skeleton(prim)
            joints = skeleton.GetJointsAttr().Get() or []
            print("  SKELETON_JOINTS", len(joints))

        binding = UsdSkel.BindingAPI(prim)
        skeleton_rel = binding.GetSkeletonRel()
        if skeleton_rel:
            targets = skeleton_rel.GetTargets()
            if targets:
                print("  SKELETON_BINDING", [str(target) for target in targets])

        blend_shapes = binding.GetBlendShapesAttr()
        if blend_shapes:
            values = blend_shapes.Get()
            if values:
                print("  BLEND_SHAPES", list(values))


if __name__ == "__main__":
    main()
