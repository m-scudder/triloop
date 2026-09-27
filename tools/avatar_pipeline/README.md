# Athevia Avatar Render Pipeline

This directory defines the production path for Athevia avatars:

**one rigged 3D athlete source -> parameterized body / materials / gear / pose -> automated transparent render -> Xcode asset catalog**

The iOS app stays lightweight and renders pre-generated images. Blender is only an offline asset factory.

## What is automated

The pipeline is designed so adding a colorway, body preset, pose, or supported outfit does not require manually exporting images.

Inputs:
- presentation
- skin tone
- body preset
- hair style and color
- sport
- top / bottom / footwear / headwear / accessory
- pose

Outputs:
- transparent PNG render
- deterministic Xcode asset name
- optional .imageset package

The deterministic asset name uses exactly the same format as `AvatarRenderAssetResolver` in the iOS app:

`AvatarRender__<presentation>__<body>__<skin>__<hair>__<hairColor>__<sport>__<top>__<bottom>__<footwear>__<headwear>__<accessory>__<pose>`

This means new generated combinations can be added without changing Swift code.

## Master Blender scene contract

The first master scene should be stored outside the app target, for example:

`art-source/avatar/athevia-athlete-master.blend`

Expected objects / data:

- Armature: `RIG__athlete`
- Camera: `CAMERA__avatar`
- Bodies:
  - `BODY__feminine`
  - `BODY__masculine`
- Body shape keys:
  - `BODY__lean`
  - `BODY__powerful`
- Hair objects:
  - `HAIR__tied`
  - later: `HAIR__cropped`, `HAIR__textured`, etc.
- Gear meshes are referenced through `config/catalog.json`.
- Pose actions:
  - `POSE__neutral`
  - `POSE__runReady`
  - `POSE__running`
  - `POSE__cycling`
  - `POSE__swimming`
  - `POSE__recovery`
  - `POSE__celebration`

Materials should expose a Principled BSDF node. The automation updates Base Color for skin / hair / colorway materials.

## First proof matrix

`config/vertical_slice.json` intentionally stays small:

- feminine
- balanced
- warm-medium skin
- tied espresso hair
- starter running outfit
- ivory-top reward state
- cobalt-shoe reward state
- neutral / run-ready / celebration poses

The goal is to prove identity consistency and automation before adding more catalog content.

## Run locally

Blender is intentionally not a runtime dependency of the iOS project.

Example on macOS:

```bash
python3 tools/avatar_pipeline/render_matrix.py \
  --blender "/Applications/Blender.app/Contents/MacOS/Blender" \
  --master "/path/to/athevia-athlete-master.blend" \
  --matrix tools/avatar_pipeline/config/vertical_slice.json \
  --catalog tools/avatar_pipeline/config/catalog.json \
  --output /tmp/athevia-avatar-renders
```

Then package the PNGs into the app asset catalog:

```bash
python3 tools/avatar_pipeline/export_xcassets.py \
  --renders /tmp/athevia-avatar-renders \
  --asset-catalog Athevia/Resources/Assets.xcassets
```

## Quality contract

All production renders must use:
- fixed 2:3 character framing inside a 3:4 transparent canvas
- identical camera transform
- identical focal length
- identical light rig
- transparent background
- full body visible
- no baked UI/background
- no identity drift between outfits or poses

Do not scale the catalog until the same athlete remains visibly identical across the full vertical-slice matrix.
