#!/usr/bin/env python3
"""Assembles Resources/Assets.xcassets from the PNGs produced by IconForge.swift.

Run after Tools/IconForge.swift so the catalog always matches the generated art.
"""
import json, os, shutil, sys

ART = sys.argv[1] if len(sys.argv) > 1 else "artifacts/art"
OUT = sys.argv[2] if len(sys.argv) > 2 else "Resources/Assets.xcassets"
INFO = {"author": "xcode", "version": 1}


def write_json(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def imageset(path, entries):
    """entries: list of (filename, scale)"""
    os.makedirs(path, exist_ok=True)
    images = []
    for filename, scale in entries:
        shutil.copyfile(os.path.join(ART, filename), os.path.join(path, os.path.basename(filename)))
        images.append({"filename": os.path.basename(filename), "idiom": "tv", "scale": scale})
    write_json(os.path.join(path, "Contents.json"), {"images": images, "info": INFO})


def imagestack(path, prefix):
    # Layers are listed front to back, which is the order tvOS parallaxes them.
    write_json(os.path.join(path, "Contents.json"), {
        "layers": [{"filename": f"{name}.imagestacklayer"} for name in ("Front", "Middle", "Back")],
        "info": INFO,
    })
    for name in ("Front", "Middle", "Back"):
        layer = os.path.join(path, f"{name}.imagestacklayer")
        write_json(os.path.join(layer, "Contents.json"), {"info": INFO})
        imageset(os.path.join(layer, "Content.imageset"),
                 [(f"{prefix}-{name}@1x.png", "1x"), (f"{prefix}-{name}@2x.png", "2x")])


if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT)
write_json(os.path.join(OUT, "Contents.json"), {"info": INFO})

brand = os.path.join(OUT, "App Icon & Top Shelf Image.brandassets")
write_json(os.path.join(brand, "Contents.json"), {
    "assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv",
         "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv",
         "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
         "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv",
         "role": "top-shelf-image", "size": "1920x720"},
    ],
    "info": INFO,
})

imagestack(os.path.join(brand, "App Icon.imagestack"), "App Icon")
imagestack(os.path.join(brand, "App Icon - App Store.imagestack"), "App Icon - App Store")
imageset(os.path.join(brand, "Top Shelf Image.imageset"),
         [("TopShelf@1x.png", "1x"), ("TopShelf@2x.png", "2x")])
imageset(os.path.join(brand, "Top Shelf Image Wide.imageset"),
         [("TopShelfWide@1x.png", "1x"), ("TopShelfWide@2x.png", "2x")])

# Full-screen launch art, shown before the animated splash scene takes over.
# tvOS marks UILaunchImages deprecated in favour of a launch storyboard, but
# storyboards cannot be compiled in this headless environment, so the launch
# image stays: it still works on tvOS 26 and costs only a build warning.
launch = os.path.join(OUT, "LaunchImage.launchimage")
os.makedirs(launch, exist_ok=True)
images = []
for filename, scale in (("Launch@1x.png", "1x"),):
    shutil.copyfile(os.path.join(ART, filename), os.path.join(launch, filename))
    images.append({
        "extent": "full-screen", "filename": filename, "idiom": "tv",
        "minimum-system-version": "9.0", "orientation": "landscape", "scale": scale,
    })
write_json(os.path.join(launch, "Contents.json"), {"images": images, "info": INFO})

print("asset catalog written to", OUT)
