#!/usr/bin/env python3
"""Validate the exported Athevia USDZ contract using Pixar USD directly."""

import argparse
import os

from pxr import Usd, UsdGeom, UsdSkel


def fail(errors):
    print("Athevia USDZ validation failed:")
    for error in errors:
        print(" -", error)
    raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--usdz", required=True)
    parser.add_argument(
        "--presentation",
        required=True,
        choices=("feminine", "masculine"),
    )
    args = parser.parse_args()

    stage = Usd.Stage.Open(args.usdz)
    if stage is None:
        raise RuntimeError("Could not open USDZ: " + args.usdz)

    errors = []

    root = "/AtheviaAthlete/RIG__athlete"
    required_xforms = [
        root + "/BODY__" + args.presentation,
        root + "/BODY__lean",
        root + "/BODY__powerful",
        root + "/HAIR__cropped",
        root + "/HAIR__swept",
        root + "/HAIR__tied",
        root + "/HAIR__textured",
        root + "/HAIR__long",
        root + "/HAIR__closeCut",
        root + "/GEAR__runTopPerformance",
        root + "/GEAR__runShort",
        root + "/GEAR__runShoe",
        root + "/FACE__eyes",
        root + "/FACE__eyebrows",
        root + "/FACE__eyelashes",
        root + "/FACE__teeth",
    ]

    for path in required_xforms:
        prim = stage.GetPrimAtPath(path)
        if not prim or not prim.IsValid():
            errors.append("missing prim: " + path)

    skeletons = [
        prim
        for prim in stage.Traverse()
        if prim.IsA(UsdSkel.Skeleton)
    ]

    if len(skeletons) != 1:
        errors.append(
            "expected exactly one shared skeleton, got "
            + str(len(skeletons))
        )
    else:
        joints = UsdSkel.Skeleton(skeletons[0]).GetJointsAttr().Get() or []
        if len(joints) < 40:
            errors.append(
                "shared skeleton has unexpectedly few joints: "
                + str(len(joints))
            )

    mesh_count = 0
    bound_mesh_count = 0

    for prim in stage.Traverse():
        binding = UsdSkel.BindingAPI(prim)

        blend_shapes = binding.GetBlendShapesAttr()
        if blend_shapes:
            values = blend_shapes.Get()
            if values:
                errors.append(
                    "unexpected runtime blend shapes on "
                    + str(prim.GetPath())
                    + ": "
                    + str(list(values))
                )

        if prim.IsA(UsdGeom.Mesh):
            mesh_count += 1

            targets = binding.GetSkeletonRel().GetTargets()
            if targets:
                bound_mesh_count += 1

            mesh = UsdGeom.Mesh(prim)
            points = mesh.GetPointsAttr().Get() or []
            if not points:
                errors.append(
                    "mesh has no points: " + str(prim.GetPath())
                )

    if mesh_count < 10:
        errors.append("unexpectedly small mesh catalog: " + str(mesh_count))

    if bound_mesh_count < 10:
        errors.append(
            "too few meshes bound to shared skeleton: "
            + str(bound_mesh_count)
        )

    if errors:
        fail(errors)

    print("Athevia USDZ validation passed.")
    print("Package:", os.path.abspath(args.usdz))
    print("Presentation:", args.presentation)
    print("Skeleton joints:", len(UsdSkel.Skeleton(skeletons[0]).GetJointsAttr().Get()))
    print("Meshes:", mesh_count)
    print("Skinned meshes:", bound_mesh_count)
    print("Runtime blend shapes: 0")


if __name__ == "__main__":
    main()
