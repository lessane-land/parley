#!/usr/bin/env python3
"""Regenerate the macOS AppIcon PNGs at Apple's template proportions.

The previous Mac icon filled ~88% of the canvas, so it rendered larger than
neighbouring Dock icons. Apple's macOS grid puts the icon body in an 824x824
area inside the 1024 canvas (~100px transparent margin) plus a soft shadow.
This reproduces the Paper `AppIconView` (squircle gradient + ink-drop + tittle)
at that size so Inkling sits the same size as every other Dock icon.
"""
import cairosvg
from PIL import Image, ImageFilter
import io

# ---- Paper palette (mirrors IconPalette.of(.paper) in SettingsView.swift) ----
BG_TOP = "#FCF8F0"
BG_BOT = "#EFE7D6"
FG     = "#3E5C50"   # ink-drop + tittle

CANVAS = 1024
BODY   = 824                       # Apple's content size inside the canvas
OX     = (CANVAS - BODY) / 2        # 100 -> centred margin
OY     = (CANVAS - BODY) / 2 - 6    # nudge up a touch to leave shadow room


def squircle_path(x0, y0, s):
    """Superellipse matching the SwiftUI `Squircle` (control fractions .09/.91)."""
    def p(fx, fy):
        return (x0 + fx * s, y0 + fy * s)
    pts = {
        "start": p(0.5, 0),
        "c1a": p(0.09, 0), "c2a": p(0, 0.09), "a": p(0, 0.5),
        "c1b": p(0, 0.91), "c2b": p(0.09, 1), "b": p(0.5, 1),
        "c1c": p(0.91, 1), "c2c": p(1, 0.91), "c": p(1, 0.5),
        "c1d": p(1, 0.09), "c2d": p(0.91, 0), "d": p(0.5, 0),
    }
    f = lambda t: f"{t[0]:.2f},{t[1]:.2f}"
    return (f"M{f(pts['start'])} "
            f"C{f(pts['c1a'])} {f(pts['c2a'])} {f(pts['a'])} "
            f"C{f(pts['c1b'])} {f(pts['c2b'])} {f(pts['b'])} "
            f"C{f(pts['c1c'])} {f(pts['c2c'])} {f(pts['c'])} "
            f"C{f(pts['c1d'])} {f(pts['c2d'])} {f(pts['d'])} Z")


def glyph_xform(x, y, size, ox, oy):
    """Reproduce InkDrop's CGAffineTransform (scale 1.08 about (50,54.5), nudge,
    fit a 108-unit board to `size`), then offset into the canvas."""
    xc = (((x - 50) * 1.08 + 50) + 4) * size / 108
    yc = (((y - 54.5) * 1.08 + 54.5) - 1.5) * size / 108
    return (xc + ox, yc + oy)


def inkdrop_path(size, ox, oy):
    # The design glyph in 0..100 space (two-cubic semicircle bottom).
    raw = [
        ("M", 50, 40),
        ("C", 58, 55, 69, 64, 69, 74),
        ("C", 69, 84.49, 60.49, 93, 50, 93),
        ("C", 39.51, 93, 31, 84.49, 31, 74),
        ("C", 31, 64, 42, 55, 50, 40),
    ]
    out = []
    for seg in raw:
        cmd = seg[0]
        coords = seg[1:]
        pts = []
        for i in range(0, len(coords), 2):
            px, py = glyph_xform(coords[i], coords[i + 1], size, ox, oy)
            pts.append(f"{px:.2f},{py:.2f}")
        out.append(cmd + " ".join(pts))
    return " ".join(out) + " Z"


def build_svg():
    body = squircle_path(OX, OY, BODY)
    drop = inkdrop_path(BODY, OX, OY)
    dot_cx = 0.50 * BODY + OX
    dot_cy = 0.1857 * BODY + OY
    dot_r  = 0.08 * BODY
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{BG_TOP}"/>
      <stop offset="1" stop-color="{BG_BOT}"/>
    </linearGradient>
  </defs>
  <path d="{body}" fill="url(#bg)"/>
  <path d="{drop}" fill="{FG}"/>
  <circle cx="{dot_cx:.2f}" cy="{dot_cy:.2f}" r="{dot_r:.2f}" fill="{FG}"/>
</svg>'''


def render():
    svg = build_svg()
    png_bytes = cairosvg.svg2png(bytestring=svg.encode(), output_width=CANVAS, output_height=CANVAS)
    art = Image.open(io.BytesIO(png_bytes)).convert("RGBA")

    # Soft drop shadow from the body silhouette.
    alpha = art.split()[3]
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda a: int(a * 0.30)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))

    base = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    base.alpha_composite(shadow, (0, 16))   # nudge the shadow below the body
    base.alpha_composite(art)
    return base


def main():
    master = render()
    sizes = {16: "icon-mac-16.png", 32: "icon-mac-32.png", 64: "icon-mac-64.png",
             128: "icon-mac-128.png", 256: "icon-mac-256.png",
             512: "icon-mac-512.png", 1024: "icon-mac-1024.png"}
    out_dir = "Parley/Assets.xcassets/AppIcon.appiconset"
    for px, name in sizes.items():
        img = master.resize((px, px), Image.LANCZOS)
        img.save(f"{out_dir}/{name}")
        print("wrote", name, px)


if __name__ == "__main__":
    main()
