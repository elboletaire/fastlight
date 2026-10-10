#!/usr/bin/env python3
"""Brighter logo variants (A/B/C) for review. Writes SVGs next to this file.

Usage: python3 generate_variants.py
"""
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "src"))
from generate import squircle, svg  # noqa: E402

BODY = squircle(100, 100, 824, 824, 185.4)


# ------------------------------------------------------------------ geometry
class Glyph:
    """Lens + trails on a 100 grid, rotated `angle` degrees about (47, 50)."""

    def __init__(self, angle=-20, ring=(62, 50, 19, 9),
                 trails=((16, 37, 35, 6.5), (8, 50, 32, 6.5), (16, 63, 35, 6.5)),
                 taper=False, spark=None):
        self.angle, self.ring, self.trails = angle, ring, trails
        self.taper, self.spark = taper, spark  # spark: (dx, dy, size) from lens centre

    def rot(self, x, y):
        a = math.radians(self.angle)
        dx, dy = x - 47, y - 50
        return 47 + dx * math.cos(a) - dy * math.sin(a), 50 + dx * math.sin(a) + dy * math.cos(a)

    def bounds(self):
        cx, cy, r, w = self.ring
        ccx, ccy = self.rot(cx, cy)
        ro = r + w / 2
        pts = [(ccx - ro, ccy - ro), (ccx + ro, ccy + ro)]
        for x1, y, x2, tw in self.trails:
            for x in (x1, x2):
                ex, ey = self.rot(x, y)
                pts += [(ex - tw / 2, ey - tw / 2), (ex + tw / 2, ey + tw / 2)]
        if self.spark:
            sx, sy, s = self.spark
            px, py = self.rot(cx + sx, cy + sy)
            pts += [(px - s, py - s), (px + s, py + s)]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)

    def trail_path(self, x1, y, x2, w):
        if not self.taper:
            return None
        # comet: needle-thin tail widening into a round head
        h = w / 2
        return (f"M{x1:g} {y - 0.4:g} L{x2:g} {y - h:g} A{h:g} {h:g} 0 0 1 {x2:g} {y + h:g} "
                f"L{x1:g} {y + 0.4:g} Z")

    def render(self, ring_paint, trail_paint, glass=None, glint=None, spark_paint=None,
               ring_w=None, trails=None):
        cx, cy, r, w = self.ring
        w = ring_w or w
        out = [f'<g transform="rotate({self.angle:g} 47 50)">']
        if glass:
            out.append(f'<circle cx="{cx:g}" cy="{cy:g}" r="{r - w / 2 + 0.3:g}" fill="{glass}"/>')
        out.append(f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="none" stroke="{ring_paint}" '
                   f'stroke-width="{w:g}"/>')
        if glint:
            gr = r - w / 2 - 3.2
            # glint arc, upper-left inside the lens (the light comes from the front-top)
            a0, a1 = math.radians(200), math.radians(250)
            out.append(f'<path d="M{cx + gr * math.cos(a0):.2f} {cy + gr * math.sin(a0):.2f} '
                       f'A{gr:g} {gr:g} 0 0 1 {cx + gr * math.cos(a1):.2f} {cy + gr * math.sin(a1):.2f}" '
                       f'fill="none" stroke="{glint}" stroke-width="2.4" stroke-linecap="round"/>')
        for x1, y, x2, tw in (trails or self.trails):
            p = self.trail_path(x1, y, x2, tw)
            if p:
                out.append(f'<path d="{p}" fill="{trail_paint}"/>')
            else:
                out.append(f'<line x1="{x1:g}" y1="{y:g}" x2="{x2:g}" y2="{y:g}" stroke="{trail_paint}" '
                           f'stroke-width="{tw:g}" stroke-linecap="round"/>')
        out.append("</g>")
        if self.spark and spark_paint:
            sx, sy, s = self.spark
            px, py = self.rot(cx + sx, cy + sy)
            k = s * 0.22
            out.append(f'<path d="M{px:.2f} {py - s:.2f} Q{px + k:.2f} {py - k:.2f} {px + s:.2f} {py:.2f} '
                       f'Q{px + k:.2f} {py + k:.2f} {px:.2f} {py + s:.2f} Q{px - k:.2f} {py + k:.2f} '
                       f'{px - s:.2f} {py:.2f} Q{px - k:.2f} {py - k:.2f} {px:.2f} {py - s:.2f}Z" '
                       f'fill="{spark_paint}"/>')
        return "".join(out)

    def place(self, scale, cx_off=0.0, cy_off=0.0):
        bx, by, bw, bh = self.bounds()
        cx, cy = bx + bw / 2 + cx_off, by + bh / 2 + cy_off
        return f"translate(512 512) scale({scale:g}) translate({-cx:.3f} {-cy:.3f})"


def lin(gid, stops, x1=0, y1=0, x2=0, y2=1, user=False):
    u = ' gradientUnits="userSpaceOnUse"' if user else ""
    s = "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a}"' if a is not None else "") + "/>"
                for o, c, a in stops)
    return f'<linearGradient id="{gid}"{u} x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>'


COMMON = (
    '<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">'
    '<feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.22"/></filter>'
    '<filter id="bloom" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="2.6"/></filter>'
    '<filter id="grain" x="0" y="0" width="100%" height="100%">'
    '<feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="7"/>'
    '<feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 0.05 0"/></filter>'
    f'<clipPath id="clip"><path d="{BODY}"/></clipPath>'
    + lin("rim", [(0, "#FFFFFF", 0.6), (0.2, "#FFFFFF", 0.1), (1, "#FFFFFF", 0.05)])
)


def icon(defs, bg_layers, glyph_svg, bloom_svg=""):
    bloom = f'<g filter="url(#bloom)" opacity="0.8">{bloom_svg}</g>' if bloom_svg else ""
    return svg(1024, 1024,
               f"<defs>{COMMON}{defs}</defs>"
               f'<g filter="url(#shadow)"><path d="{BODY}" fill="#000"/></g>'
               f'<g clip-path="url(#clip)">{bg_layers}'
               f'<rect x="100" y="100" width="824" height="824" filter="url(#grain)"/></g>'
               f'<path d="{BODY}" fill="none" stroke="url(#rim)" stroke-width="4"/>'
               f"{bloom}{glyph_svg}", title="Fastlight")


def tile(defs, bg, glyph_svg):
    """Simplified flat icon for 16/32 px."""
    return svg(1024, 1024, f"<defs>{defs}</defs><path d=\"{BODY}\" fill=\"{bg}\"/>{glyph_svg}")


def template(g, size, ring_w=None, trails=None):
    import copy
    gg = copy.copy(g)
    if trails:
        gg.trails = trails
    if ring_w:
        gg.ring = (*g.ring[:3], ring_w)
    bx, by, bw, bh = gg.bounds()
    side = max(bw, bh) * 1.08
    cx, cy = bx + bw / 2, by + bh / 2
    return svg(size, size, gg.render("#000", "#000", spark_paint="#000"),
               view=f"{cx - side / 2:.3f} {cy - side / 2:.3f} {side:.3f} {side:.3f}")


# ------------------------------------------------------------------ A: Daylight
def variant_a():
    """Daylight: vivid azure -> violet sky, crisp white lens, glowing sun-yellow trails."""
    g = Glyph(angle=-28, ring=(62, 50, 18, 7.5),
              trails=((18, 37, 37, 6.5), (8, 50, 35, 6.5), (20, 63, 37, 6.5)))
    defs = (lin("bg", [(0, "#2FB6FF", None), (0.5, "#4D6BFF", None), (1, "#7A3DF0", None)], 0, 0, 1, 1)
            + '<radialGradient id="sun" gradientUnits="userSpaceOnUse" cx="640" cy="380" r="520">'
              '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.35"/>'
              '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>'
            + lin("tr", [(0, "#FFE15A", 0), (0.55, "#FFD43B", 0.9), (1, "#FFF3B0", None)], 6, 0, 38, 0, user=True))
    place = g.place(7.4)
    glyph_svg = (f'<g transform="{place}">'
                 + g.render("#FFFFFF", "url(#tr)", glass="#FFFFFF33", glint="#FFFFFF") + "</g>")
    bloom = f'<g transform="{place}">' + g.render("#FFFFFF", "#FFC21A") + "</g>"
    big = icon(defs, '<rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>'
                     '<rect x="100" y="100" width="824" height="824" fill="url(#sun)"/>', glyph_svg, bloom)
    small_tr = ((14, 40, 33, 10), (20, 61, 34, 10))
    gs = Glyph(angle=-28, ring=(62, 50, 18, 10.5), trails=small_tr)
    small = tile(lin("bg", [(0, "#2FB6FF", None), (1, "#6A45F5", None)], 0, 0, 1, 1), "url(#bg)",
                 f'<g transform="{gs.place(8.3)}">' + gs.render("#FFFFFF", "#FFD43B") + "</g>")
    return big, small, g, gs


# ------------------------------------------------------------------ B: Sunrise
def variant_b():
    """Sunrise: tangerine -> coral -> magenta, cream lens, white-hot trails climbing steeply."""
    g = Glyph(angle=-34, ring=(62, 50, 18, 8),
              trails=((16, 37, 36, 7), (6, 50, 34, 7), (18, 63, 36, 7)))
    defs = (lin("bg", [(0, "#FF3D8B", None), (0.5, "#FF6A4D", None), (1, "#FFB733", None)], 0.9, 0, 0.1, 1)
            + '<radialGradient id="sun" gradientUnits="userSpaceOnUse" cx="600" cy="420" r="460">'
              '<stop offset="0" stop-color="#FFF2C2" stop-opacity="0.55"/>'
              '<stop offset="1" stop-color="#FFF2C2" stop-opacity="0"/></radialGradient>'
            + lin("tr", [(0, "#FFFFFF", 0), (0.6, "#FFF6DD", 0.95), (1, "#FFFFFF", None)], 4, 0, 38, 0, user=True)
            + lin("ring", [(0, "#FFE6B0", None), (1, "#FFFFFF", None)], 40, 70, 84, 30, user=True))
    place = g.place(7.4)
    glyph_svg = (f'<g transform="{place}">'
                 + g.render("url(#ring)", "url(#tr)", glass="#FFFFFF2E", glint="#FFFFFF") + "</g>")
    bloom = f'<g transform="{place}">' + g.render("#FFF1C9", "#FFE7A8") + "</g>"
    big = icon(defs, '<rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>'
                     '<rect x="100" y="100" width="824" height="824" fill="url(#sun)"/>', glyph_svg, bloom)
    gs = Glyph(angle=-34, ring=(62, 50, 18, 10.5), trails=((14, 40, 33, 10), (20, 61, 34, 10)))
    small = tile(lin("bg", [(0, "#FF4D80", None), (1, "#FFA733", None)], 0.9, 0, 0.1, 1), "url(#bg)",
                 f'<g transform="{gs.place(8.3)}">' + gs.render("#FFFFFF", "#FFFFFF") + "</g>")
    return big, small, g, gs


# ------------------------------------------------------------------ C: Comet
def variant_c():
    """Comet: light, airy tile; gradient lens with a spark at its leading edge,
    tapered comet trails that clearly rise. Optimistic, daytime, Tahoe-light."""
    g = Glyph(angle=-30, ring=(62, 50, 18, 7.5),
              trails=((14, 37, 38, 8), (4, 50, 36, 8), (18, 63, 38, 8)),
              taper=True, spark=(17, -17, 6.5))
    defs = (lin("bg", [(0, "#FFFFFF", None), (1, "#EAF0FF", None)])
            + '<radialGradient id="halo" gradientUnits="userSpaceOnUse" cx="600" cy="440" r="420">'
              '<stop offset="0" stop-color="#FFC24D" stop-opacity="0.28"/>'
              '<stop offset="1" stop-color="#FFC24D" stop-opacity="0"/></radialGradient>'
            + lin("ring", [(0, "#FF8A3D", None), (0.5, "#FF4F8B", None), (1, "#7B5CFF", None)],
                  38, 72, 86, 28, user=True)
            + lin("tr", [(0, "#FFB13B", 0), (0.5, "#FF9A3C", 0.85), (1, "#FF6E5A", None)], 4, 0, 40, 0, user=True)
            + '<radialGradient id="glass" gradientUnits="userSpaceOnUse" cx="56" cy="44" r="14">'
              '<stop offset="0" stop-color="#FFFFFF" stop-opacity="1"/>'
              '<stop offset="1" stop-color="#FFE3EC" stop-opacity="1"/></radialGradient>')
    place = g.place(7.3)
    glyph_svg = (f'<g transform="{place}">'
                 + g.render("url(#ring)", "url(#tr)", glass="url(#glass)", glint="#FF9FBF",
                            spark_paint="#FFB300") + "</g>")
    bloom = f'<g transform="{place}" opacity="0.4">' + g.render("#FF6E8A", "#FFB13B", spark_paint="#FFD25A") + "</g>"
    big = icon(defs, '<rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>'
                     '<rect x="100" y="100" width="824" height="824" fill="url(#halo)"/>', glyph_svg, bloom)
    gs = Glyph(angle=-30, ring=(62, 50, 18, 10.5), trails=((12, 40, 34, 11), (18, 61, 35, 11)),
               taper=True, spark=(17, -17, 7))
    small = tile(lin("ring", [(0, "#FF7A3D", None), (1, "#7B5CFF", None)], 38, 72, 86, 28, user=True),
                 "#FFFFFF",
                 f'<path d="{BODY}" fill="none" stroke="#D5DBEA" stroke-width="12"/>'
                 f'<g transform="{gs.place(8.3)}">' + gs.render("url(#ring)", "#FF8A3D", spark_paint="#FFB300") + "</g>")
    return big, small, g, gs


def main():
    for name, fn, mb in (("a-daylight", variant_a, None), ("b-sunrise", variant_b, None),
                         ("c-comet", variant_c, None)):
        big, small, g, gs = fn()
        (HERE / f"{name}-app-icon.svg").write_text(big)
        (HERE / f"{name}-app-icon-small.svg").write_text(small)
        (HERE / f"{name}-menubar-36.svg").write_text(template(g, 36, ring_w=9))
        (HERE / f"{name}-menubar-18.svg").write_text(template(gs, 18, ring_w=11))
        print("wrote", name)


if __name__ == "__main__":
    main()
