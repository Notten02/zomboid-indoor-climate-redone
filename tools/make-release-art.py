#!/usr/bin/env python3
"""Generates the mod's icon, poster and Workshop preview. Original artwork, drawn from scratch with Pillow.

    python3 tools/make-release-art.py            writes the three files below
    python3 tools/make-release-art.py --out DIR  writes them under DIR instead (a scratch check)

Outputs (paths relative to the repo root):
    Contents/mods/IndoorClimateRedone/42/icon.png     256x256 RGBA  mod.info icon=
    Contents/mods/IndoorClimateRedone/42/poster.png   512x512 RGB   mod.info poster=
    preview.png                                       256x256 RGB   Workshop item preview (the in-game uploader
                                                                    demands exactly 256x256 and at most 1000 KB)

The motif is a house glowing warm on a cold, snowy night, with heat waves rising inside it. No Project Zomboid art or
name is used, and nothing is taken from the original mod's poster.

Needs only Python 3 and Pillow (`pip install --user pillow` or the distro package). Text uses the first of a few common
bold sans-serif fonts that is installed (DejaVu, Liberation, Noto), else Pillow's built-in font, so the lettering can
differ a little between machines. Everything is drawn at 4x and scaled down for smooth edges. The snow is placed by a
fixed seed, so the output is the same on every run.
"""
import argparse
import math
import os
import random
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("Pillow is required: pip install --user pillow (or your distro's python-pillow package)")

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MOD_DIR = os.path.join(REPO, "Contents", "mods", "IndoorClimateRedone", "42")
SS = 4  # supersampling factor

NIGHT_TOP = (16, 28, 48)
NIGHT_BOTTOM = (7, 11, 20)
SNOW = (214, 230, 246)
WALL_OUTLINE = (58, 30, 14)
WARM_TOP = (255, 196, 96)
WARM_BOTTOM = (226, 92, 34)
WAVE = (255, 244, 222)
TEXT = (238, 242, 248)
ACCENT = (255, 160, 64)
TEXT_DIM = (150, 168, 192)

FONT_CANDIDATES = [
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "/Library/Fonts/Arial Bold.ttf",
]


def font(px):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, px)
    try:
        return ImageFont.load_default(px)
    except TypeError:  # Pillow older than 10.1 has no sized built-in font
        return ImageFont.load_default()


def lerp(a, b, t):
    return a + (b - a) * t


def vertical_gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        px.line([(0, y), (w, y)], fill=tuple(int(lerp(top[i], bottom[i], t)) for i in range(3)))
    return img


def night(size, snow=True):
    """The cold night sky with a few snowflakes, at supersampled size."""
    s = size * SS
    img = vertical_gradient(s, s, NIGHT_TOP, NIGHT_BOTTOM).convert("RGBA")
    if snow:
        rng = random.Random(42)
        flakes = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        fd = ImageDraw.Draw(flakes)
        for _ in range(70):
            x, y = rng.uniform(0, s), rng.uniform(0, s)
            r = rng.uniform(0.004, 0.011) * s
            alpha = int(rng.uniform(60, 190))
            fd.ellipse([x - r, y - r, x + r, y + r], fill=SNOW + (alpha,))
        img.alpha_composite(flakes.filter(ImageFilter.GaussianBlur(s * 0.0015)))
    return img


def house_polygon(cx, top, w, h):
    """A house front: a roof triangle over a body. `top` is the roof's peak, w the body's width, h the full height."""
    roof_h = h * 0.40
    eave = w * 0.10
    left, right = cx - w / 2, cx + w / 2
    base = top + h
    shoulder = top + roof_h
    return [
        (cx, top),
        (right + eave, shoulder),
        (right, shoulder),
        (right, base),
        (left, base),
        (left, shoulder),
        (left - eave, shoulder),
    ]


def wave_points(x, y0, y1, amp, turns=1.5, steps=60):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        pts.append((x + amp * math.sin(t * turns * 2 * math.pi), lerp(y0, y1, t)))
    return pts


def draw_polyline(draw, pts, width, fill):
    for a, b in zip(pts, pts[1:]):
        draw.line([a, b], fill=fill, width=int(width))
    rad = width / 2
    for x, y in pts:
        draw.ellipse([x - rad, y - rad, x + rad, y + rad], fill=fill)


def draw_house(img, cx, top, w, h):
    """The glowing house with three heat waves inside, onto img (RGBA, supersampled)."""
    s = img.width
    poly = house_polygon(cx, top, w, h)

    # Warm light spilling into the night around the house.
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(poly, fill=ACCENT + (150,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(w * 0.16)))

    # Body: a dark outline, then the warm gradient a little smaller.
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    outline = Image.new("RGBA", img.size, WALL_OUTLINE + (255,))
    img.paste(outline, (0, 0), mask)
    inner = mask.filter(ImageFilter.MinFilter(max(3, int(w * 0.05) // 2 * 2 + 1)))
    warm = vertical_gradient(s, s, WARM_TOP, WARM_BOTTOM).convert("RGBA")
    span = Image.new("RGBA", img.size, (0, 0, 0, 0))
    span.paste(warm.resize((s, int(h))), (0, int(top)))
    img.paste(span, (0, 0), inner)

    # Snow on the roof.
    peak, right_eave, left_eave = poly[0], poly[1], poly[6]
    cap = Image.new("RGBA", img.size, (0, 0, 0, 0))
    cd = ImageDraw.Draw(cap)
    thick = w * 0.06
    draw_polyline(cd, [left_eave, peak, right_eave], thick, SNOW + (255,))
    img.alpha_composite(cap)

    # Heat waves rising inside the body.
    body_top = top + h * 0.48
    body_bottom = top + h * 0.90
    waves = Image.new("RGBA", img.size, (0, 0, 0, 0))
    wd = ImageDraw.Draw(waves)
    for dx in (-0.24, 0.0, 0.24):
        pts = wave_points(cx + w * dx, body_bottom, body_top, w * 0.045)
        draw_polyline(wd, pts, w * 0.055, WAVE + (255,))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.paste((120, 40, 10, 120), (0, 0), waves.getchannel("A"))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(w * 0.02)))
    img.alpha_composite(waves)


def fit_text(draw, text, max_w, start_px):
    px = start_px
    while px > 6:
        f = font(px)
        box = draw.textbbox((0, 0), text, font=f)
        if box[2] - box[0] <= max_w:
            return f, box
        px -= 2
    f = font(6)
    return f, draw.textbbox((0, 0), text, font=f)


def centered_text(img, text, cy, max_w, start_px, fill, shadow=True):
    draw = ImageDraw.Draw(img)
    f, box = fit_text(draw, text, max_w, start_px)
    w, h = box[2] - box[0], box[3] - box[1]
    x = (img.width - w) / 2 - box[0]
    y = cy - h / 2 - box[1]
    if shadow:
        draw.text((x + SS, y + SS * 1.5), text, font=f, fill=(0, 0, 0, 200))
    draw.text((x, y), text, font=f, fill=fill)


def make_icon(size=256):
    s = size * SS
    img = night(size, snow=False)
    draw_house(img, s * 0.5, s * 0.14, s * 0.56, s * 0.72)
    # Rounded-square plate with transparent corners and a thin warm rim.
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.18), fill=255)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    rim = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([SS, SS, s - SS - 1, s - SS - 1], radius=int(s * 0.18),
                                          outline=WALL_OUTLINE + (255,), width=SS * 3)
    out.alpha_composite(rim)
    return out.resize((size, size), Image.LANCZOS)


def make_poster(size=512, subtitle=True):
    s = size * SS
    img = night(size)
    draw_house(img, s * 0.5, s * 0.08, s * 0.44, s * 0.56)
    centered_text(img, "INDOOR CLIMATE", s * 0.745, s * 0.84, int(s * 0.092), TEXT + (255,))
    centered_text(img, "REDONE", s * 0.855, s * 0.60, int(s * 0.125), ACCENT + (255,))
    if subtitle:
        centered_text(img, "ROOMS  \u00b7  HEATERS  \u00b7  MULTIPLAYER", s * 0.943, s * 0.84,
                      int(s * 0.036), TEXT_DIM + (255,), shadow=False)
    return img.convert("RGB").resize((size, size), Image.LANCZOS)


def save_png(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG", optimize=True)
    shown = os.path.relpath(path, REPO) if path.startswith(REPO) else path
    print(f"wrote {shown}  {img.size[0]}x{img.size[1]}  {os.path.getsize(path)} bytes")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", help="write under this directory instead of the repo (same relative layout)")
    args = ap.parse_args()
    root = os.path.abspath(args.out) if args.out else REPO
    mod_dir = os.path.join(root, os.path.relpath(MOD_DIR, REPO))

    save_png(make_icon(256), os.path.join(mod_dir, "icon.png"))
    save_png(make_poster(512), os.path.join(mod_dir, "poster.png"))
    # The in-game uploader requires exactly 256x256 and at most 1000 KB (vanilla UI_WorkshopError_Preview*).
    preview = make_poster(256, subtitle=False)
    path = os.path.join(root, "preview.png")
    save_png(preview, path)
    assert preview.size == (256, 256) and os.path.getsize(path) <= 1000 * 1000


if __name__ == "__main__":
    main()
