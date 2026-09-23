#!/usr/bin/env python3
"""Regenerates Resources/dmg/background.png (+@2x). Needs Pillow and Inter font files.
Usage: python3 scripts/make_dmg_background.py /path/to/inter/ttf
Layout must match scripts/dmg_settings.py (window 660x420, icons at y=200)."""
import sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
W, H = 660, 420
APP_X, APPS_X, ICON_Y = 170, 490, 200

def render(scale):
    w, h = W * scale, H * scale
    s = lambda v: int(round(v * scale))
    img = Image.new("RGB", (w, h))
    px = img.load()
    top, bot = (255, 251, 247), (250, 238, 229)
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    img = img.convert("RGBA")

    # soft warm glow behind the arrow
    ga = Image.new("L", (w, h), 0)
    ImageDraw.Draw(ga).ellipse([s(220), s(140), s(440), s(260)], fill=70)
    glow = Image.new("RGBA", (w, h), (255, 170, 110, 0))
    glow.putalpha(ga.filter(ImageFilter.GaussianBlur(s(50))))
    img.alpha_composite(glow)

    # arrow: gradient shaft + rounded chevron, drawn 4x then downsampled for smooth edges
    ss = 4
    A = Image.new("L", (w * ss, h * ss), 0)
    ad = ImageDraw.Draw(A)
    k = lambda v: v * scale * ss
    y = ICON_Y - 2
    x0, x1 = 268, 392
    lw = 7
    ad.line([k(x0), k(y), k(x1), k(y)], fill=255, width=int(k(lw)))
    for (cx, cy) in [(x0, y), (x1, y)]:
        ad.ellipse([k(cx - lw / 2), k(cy - lw / 2), k(cx + lw / 2), k(cy + lw / 2)], fill=255)
    hl = 20
    for dy in (-1, 1):
        ex, ey = x1 - hl, y + dy * hl
        ad.line([k(x1), k(y), k(ex), k(ey)], fill=255, width=int(k(lw)))
        ad.ellipse([k(ex - lw / 2), k(ey - lw / 2), k(ex + lw / 2), k(ey + lw / 2)], fill=255)
    A = A.resize((w, h), Image.LANCZOS)

    grad = Image.new("RGBA", (w, h))
    gp = grad.load()
    c0, c1 = (255, 190, 70), (232, 52, 48)
    for xx in range(w):
        t = min(1, max(0, (xx / scale - x0) / (x1 - x0)))
        c = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)) + (255,)
        for yy in range(s(y - 30), s(y + 30)):
            gp[xx, yy] = c
    # shadow under arrow
    sh = Image.new("RGBA", (w, h), (235, 90, 60, 0))
    sh.putalpha(A.point(lambda v: int(v * 0.30)).filter(ImageFilter.GaussianBlur(s(6))))
    img.alpha_composite(sh, (0, s(4)))
    arrow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    arrow.paste(grad, (0, 0), A)
    img.alpha_composite(arrow)

    # text
    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(f"{FONT_DIR}/InterDisplay-Bold.ttf", s(26))
    sub = ImageFont.truetype(f"{FONT_DIR}/Inter-Medium.ttf", s(13))
    d.text((w / 2, s(58)), "Based", font=title, fill=(40, 26, 22), anchor="mm")
    d.text((w / 2, s(86)), "Drag into Applications to install", font=sub, fill=(150, 128, 118), anchor="mm")

    # faint landing pads under each icon
    pads = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pads)
    for cx in (APP_X, APPS_X):
        pd.rounded_rectangle([s(cx - 84), s(ICON_Y - 80), s(cx + 84), s(ICON_Y + 104)],
                             radius=s(28), fill=(255, 255, 255, 150), outline=(200, 120, 90, 40), width=max(1, s(1)))
    img.alpha_composite(pads)
    return img.convert("RGB")

render(1).save("Resources/dmg/background.png", dpi=(72, 72))
render(2).save("Resources/dmg/background@2x.png", dpi=(144, 144))
print("ok")
