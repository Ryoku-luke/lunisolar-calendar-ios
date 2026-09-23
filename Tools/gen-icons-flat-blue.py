#!/usr/bin/env python3
"""
gen-icons-flat-blue.py
生成扁平化、淡蓝色渐变风格的 iOS App 图标全套尺寸。

设计语言：
- 主图标 AppIcon：淡蓝色对角渐变（#BFE3F5 → #5BA8E0），中央白色月相+日历网格极简组合
- 春节限定 AppIconSpringFestival：暖红金渐变（#C73E3A → #E8A93C），中央白色"福"字

输出：
  Assets/Assets.xcassets/AppIcon.appiconset/Icon-*.png
  Assets/Assets.xcassets/AppIconSpringFestival.appiconset/Icon-*.png
  Assets/Brand/app-icon-primary.png  (1024 源图)
  Assets/Brand/app-icon-spring-festival.png (1024 源图)

所有 PNG 为 RGB 无 alpha 通道（App Store 1024 要求）。
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SIZES = [
    ("Icon-20.png", 20), ("Icon-20@2x.png", 40), ("Icon-20@3x.png", 60),
    ("Icon-29.png", 29), ("Icon-29@2x.png", 58), ("Icon-29@3x.png", 87),
    ("Icon-40.png", 40), ("Icon-40@2x.png", 80), ("Icon-40@3x.png", 120),
    ("Icon-60@2x.png", 120), ("Icon-60@3x.png", 180),
    ("Icon-76.png", 76), ("Icon-76@2x.png", 152),
    ("Icon-83.5@2x.png", 167), ("Icon-1024.png", 1024),
]

# ---- 颜色 ----
BLUE_TOP = (191, 227, 245)   # #BFE3F5 浅淡蓝
BLUE_BOT = (91, 168, 224)    # #5BA8E0 中蓝
WHITE = (255, 255, 255)

RED_TOP = (199, 62, 58)      # #C73E3A 中国红
RED_BOT = (232, 169, 60)     # #E8A93C 金黄


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size, top, bottom):
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1)) if size > 1 else 0
            t = max(0.0, min(1.0, t))
            px[x, y] = lerp(top, bottom, t)
    return img


def radial_glow(size, color, max_radius_ratio=0.55, intensity=0.18):
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gp = glow.load()
    cx = cy = size / 2
    max_r = size * max_radius_ratio
    for y in range(size):
        for x in range(size):
            d = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            if d <= max_r:
                t = 1 - d / max_r
                a = int(255 * intensity * t)
                gp[x, y] = (color[0], color[1], color[2], a)
    return glow


def draw_primary_icon(size):
    """主图标：淡蓝渐变 + 白色月相 + 日历网格（纯几何，无文字）。"""
    img = diagonal_gradient(size, BLUE_TOP, BLUE_BOT).convert("RGBA")
    glow = radial_glow(size, WHITE, 0.62, 0.10)
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    s = size
    cx = s / 2

    # ---- 月相圆（上方，白色实心）----
    moon_r = s * 0.22
    moon_cy = s * 0.36
    d.ellipse([cx - moon_r, moon_cy - moon_r, cx + moon_r, moon_cy + moon_r], fill=WHITE)

    # 月相阴影：右侧偏移圆遮挡，制造新月效果
    shadow_color = lerp(BLUE_TOP, BLUE_BOT, 0.35)
    shadow_r = moon_r * 0.88
    shadow_cx = cx + moon_r * 0.5
    d.ellipse([shadow_cx - shadow_r, moon_cy - shadow_r,
               shadow_cx + shadow_r, moon_cy + shadow_r], fill=shadow_color + (255,))

    # ---- 日历网格（下方，3×2 点阵）----
    grid_cy = s * 0.70
    dot_r = max(1, s * 0.022)
    gap = s * 0.085
    for row in range(2):
        for col in range(3):
            dx = cx + (col - 1) * gap
            dy = grid_cy + (row - 0.5) * gap * 0.95
            d.ellipse([dx - dot_r, dy - dot_r, dx + dot_r, dy + dot_r], fill=WHITE)

    return img.convert("RGB")


def draw_spring_icon(size):
    """春节限定：红金渐变 + 白色"福"字。"""
    img = diagonal_gradient(size, RED_TOP, RED_BOT).convert("RGBA")
    glow = radial_glow(size, (255, 240, 200), 0.62, 0.13)
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)

    cx = size / 2
    text = "福"
    font_size = int(size * 0.58)
    font = _load_font(font_size, prefer_cjk=True)
    if font is not None:
        bbox = d.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        tx = cx - tw / 2 - bbox[0]
        ty = (size - th) / 2 - bbox[1] - size * 0.03
        d.text((tx, ty), text, font=font, fill=WHITE)
    else:
        # fallback：灯笼形（椭圆+顶帽+底坠）
        lw = size * 0.42
        lh = size * 0.5
        d.ellipse([cx - lw / 2, size / 2 - lh / 2, cx + lw / 2, size / 2 + lh / 2], fill=WHITE)
        cap_w = size * 0.3
        d.rectangle([cx - cap_w / 2, size / 2 - lh / 2 - size * 0.04,
                     cx + cap_w / 2, size / 2 - lh / 2], fill=WHITE)

    return img.convert("RGB")


def _load_font(size, prefer_cjk=False):
    candidates = []
    if prefer_cjk:
        candidates += [
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
            "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc",
            "/System/Library/Fonts/PingFang.ttc",
            "/System/Library/Fonts/STHeiti Medium.ttc",
        ]
    candidates += [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return None


def save_png(img, path):
    img.save(path, "PNG", optimize=True)


def main():
    primary_dir = os.path.join(ROOT, "Assets", "Assets.xcassets", "AppIcon.appiconset")
    spring_dir = os.path.join(ROOT, "Assets", "Assets.xcassets", "AppIconSpringFestival.appiconset")
    brand_dir = os.path.join(ROOT, "Assets", "Brand")
    for d in (primary_dir, spring_dir, brand_dir):
        os.makedirs(d, exist_ok=True)

    print("[1/2] 主图标（淡蓝渐变 + 月相 + 日历点阵）...")
    src = draw_primary_icon(1024)
    save_png(src, os.path.join(brand_dir, "app-icon-primary.png"))
    for name, px in SIZES:
        save_png(draw_primary_icon(px), os.path.join(primary_dir, name))
    print(f"  生成 {len(SIZES)} 个档位 + 1024 源图")

    print("[2/2] 春节限定（红金渐变 + 福字）...")
    src = draw_spring_icon(1024)
    save_png(src, os.path.join(brand_dir, "app-icon-spring-festival.png"))
    for name, px in SIZES:
        save_png(draw_spring_icon(px), os.path.join(spring_dir, name))
    print(f"  生成 {len(SIZES)} 个档位 + 1024 源图")

    print("\n完成")


if __name__ == "__main__":
    main()
