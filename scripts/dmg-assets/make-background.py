#!/usr/bin/env python3
"""Render the Droidective DMG installer-window background.

A clean, light installer backdrop (a soft near-white gradient) with a bold
"drag and drop" swoosh arrow pointing from the app toward the Applications
folder. The arrow and heading are dark slate for high contrast. The two icons
and their labels are drawn by Finder on top (positions come from
scripts/dmg-settings.py); this image only paints the backdrop, heading, and
arrow.

The background must be opaque — Finder does not render a transparent DMG
background, and it doesn't switch backgrounds by system appearance, so this one
light image is shown in both Light and Dark Mode (Finder still draws the icon
labels adaptively).

Outputs background@2x.png (1200x800) next to this script. The committed
.DS_Store (authored once with create-dmg — see README.md) references this file
at .background/background@2x.png; scripts/package-dmg.sh assembles the DMG
around it with hdiutil.

Run:  uv run --with pillow scripts/dmg-assets/make-background.py
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFont

# Logical window-content size (points). The icon positions in dmg-settings.py
# are in this same coordinate space.
W, H = 600, 400

FONT = "/System/Library/Fonts/SFNS.ttf"
SS = 3  # supersample factor, downsampled at the end for smooth edges

# Soft, near-white gradient; dark slate ink for arrow + heading.
TOP = (251, 252, 252)
BOTTOM = (238, 241, 240)
INK = (43, 51, 56)


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _cubic(p0, p1, p2, p3, steps):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def _thick_curve(draw, pts, width, fill):
    """Draw a polyline with round joints/caps so the swoosh reads as one stroke."""
    r = width / 2
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        draw.line((x0, y0, x1, y1), fill=fill, width=width)
    for x, y in pts:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def render(scale: int) -> Image.Image:
    s = scale * SS
    w, h = W * s, H * s
    img = Image.new("RGB", (w, h), TOP)
    px = img.load()
    for y in range(h):  # vertical gradient
        row = _lerp(TOP, BOTTOM, y / (h - 1))
        for x in range(w):
            px[x, y] = row
    draw = ImageDraw.Draw(img)

    # Bold swoosh arrow: app (left) -> Applications (right), dipping in the middle.
    pts = _cubic((224 * s, 178 * s), (276 * s, 208 * s), (332 * s, 200 * s), (382 * s, 165 * s), 140)
    tip = pts[-1]
    hl = 24 * s  # arrowhead length

    # Trim the stroke to end one arrowhead-length back from the tip, so the
    # stroke's round end-cap is fully hidden under the head (no stray circle).
    cut, acc = 0, 0.0
    for i in range(len(pts) - 1, 0, -1):
        acc += math.dist(pts[i], pts[i - 1])
        if acc >= hl * 0.9:
            cut = i
            break
    _thick_curve(draw, pts[: cut + 1], max(1, round(7 * s)), INK)

    # Solid arrowhead, oriented along the tangent into the tip.
    ang = math.atan2(tip[1] - pts[cut][1], tip[0] - pts[cut][0])
    left = (tip[0] - hl * math.cos(ang - 0.42), tip[1] - hl * math.sin(ang - 0.42))
    right = (tip[0] - hl * math.cos(ang + 0.42), tip[1] - hl * math.sin(ang + 0.42))
    draw.polygon([tip, left, right], fill=INK)

    # Heading, centered, with a touch of letter-spacing.
    text = "drag and drop"
    font = ImageFont.truetype(FONT, round(23 * s))
    tracking = round(1.5 * s)
    widths = [draw.textlength(c, font=font) for c in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x = (w - total) / 2
    for c, cw in zip(text, widths):
        draw.text((x, 78 * s), c, font=font, fill=INK)
        x += cw + tracking

    return img.resize((W * scale, H * scale), Image.LANCZOS)


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    render(2).save(os.path.join(here, "background@2x.png"))
    print("wrote background@2x.png")


if __name__ == "__main__":
    main()
