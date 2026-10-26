#!/usr/bin/env python3
"""Create platform icon sizes from the approved wizard-hat artwork."""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
IOS_ICON = ROOT / "ios/AgentMailbox/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
MAC_DIR = ROOT / "macos"



def main() -> None:
    master = Image.open(MAC_DIR / "WizardHat-source.png").convert("RGBA").resize((1024, 1024), Image.Resampling.LANCZOS)
    IOS_ICON.parent.mkdir(parents=True, exist_ok=True)
    master.save(IOS_ICON, "PNG")
    iconset = MAC_DIR / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in sizes.items():
        master.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name, "PNG")
    print(IOS_ICON)
    print(iconset)


if __name__ == "__main__":
    main()
