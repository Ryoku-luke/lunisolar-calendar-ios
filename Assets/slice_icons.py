#!/usr/bin/env python3
"""将 2048x2048 源图标切成 Xcode AppIcon 所需的全部尺寸 PNG。"""
from PIL import Image
import os

# filename -> 像素尺寸
TARGETS = {
    "Icon-20.png":       20,
    "Icon-20@2x.png":    40,
    "Icon-20@3x.png":    60,
    "Icon-29.png":       29,
    "Icon-29@2x.png":    58,
    "Icon-29@3x.png":    87,
    "Icon-40.png":       40,
    "Icon-40@2x.png":    80,
    "Icon-40@3x.png":   120,
    "Icon-60@2x.png":   120,
    "Icon-60@3x.png":   180,
    "Icon-76.png":       76,
    "Icon-76@2x.png":   152,
    "Icon-83.5@2x.png": 167,
    "Icon-1024.png":   1024,
}

def process(source_path, out_dir):
    img = Image.open(source_path).convert("RGBA")
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))

    os.makedirs(out_dir, exist_ok=True)
    for name, px in TARGETS.items():
        resized = img.resize((px, px), Image.LANCZOS)
        out_path = os.path.join(out_dir, name)
        resized.save(out_path, "PNG")
        print(f"  {name}: {px}x{px}")

print("=== Primary icon ===")
process("/workspace/Assets/Brand/icon-primary-source.jpg",
        "/workspace/Assets/XCAssets/AppIcon.appiconset")

print("=== Spring Festival icon ===")
process("/workspace/Assets/Brand/icon-spring-source.jpg",
        "/workspace/Assets/XCAssets/AppIconSpringFestival.appiconset")

print("Done.")
