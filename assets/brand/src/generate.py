#!/usr/bin/env python3
"""Generate the Fastlight brand SVG sources in assets/brand/.

The SVGs are committed; you only need this when changing the design.
Run through `scripts/render-brand.sh --svg` (it supplies fontTools and
uharfbuzz via uv and downloads Sora, used for the outlined wordmark, and
Inter, used for body text in the DMG background).

Usage: generate.py <path-to-Sora[wght].ttf> <out-dir> <path-to-Inter[opsz,wght].ttf>

Design: "Comet" — a lens launching up and to the right, trailing three
tapered comet tails, with a gold spark at its leading edge, on a graphite
tile lit by a pink/violet glow.
"""
import copy
import math
import sys
from pathlib import Path

# ---------------------------------------------------------------- palette
GRAPHITE_950 = "#15161B"
GRAPHITE_900 = "#1E1F25"
GRAPHITE_800 = "#2A2B33"
GRAPHITE_700 = "#34353F"
GRAPHITE_500 = "#5C5E6B"

ORANGE = "#FF9A3D"      # ring start / trail head
PINK = "#FF5C9A"        # ring middle, glow
VIOLET = "#7B5CFF"      # ring end on light backgrounds
LAVENDER = "#A88BFF"    # ring end on dark backgrounds
TRAIL_TAIL = "#FFB13B"
TRAIL_HEAD = "#FF7A50"
SPARK = "#FFC81A"       # gold spark on dark
SPARK_LIGHT = "#F5A300"  # gold spark on light (a touch deeper)
FOG = "#F5F3EE"         # wordmark / text on dark

# ---------------------------------------------------------------- geometry
PIVOT = (47.0, 50.0)


class Glyph:
    """Lens + tapered trails + spark on a 100 grid, rotated about PIVOT."""

    def __init__(self, angle=-30.0, ring=(62.0, 50.0, 18.0, 7.5),
                 trails=((14, 37, 38, 8), (4, 50, 36, 8), (18, 63, 38, 8)),
                 spark=(17.0, -17.0, 6.5)):
        self.angle, self.ring, self.trails, self.spark = angle, ring, trails, spark

    def with_(self, **kw):
        g = copy.copy(self)
        for k, v in kw.items():
            setattr(g, k, v)
        return g

    def rot(self, x, y):
        a = math.radians(self.angle)
        dx, dy = x - PIVOT[0], y - PIVOT[1]
        return (PIVOT[0] + dx * math.cos(a) - dy * math.sin(a),
                PIVOT[1] + dx * math.sin(a) + dy * math.cos(a))

    def spark_pos(self):
        cx, cy, _, _ = self.ring
        sx, sy, s = self.spark
        px, py = self.rot(cx + sx, cy + sy)
        return px, py, s

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
            px, py, s = self.spark_pos()
            pts += [(px - s, py - s), (px + s, py + s)]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)

    def centre(self):
        bx, by, bw, bh = self.bounds()
        return bx + bw / 2, by + bh / 2

    @staticmethod
    def trail_path(x1, y, x2, w):
        # comet tail: needle-thin end widening into a round head
        h = w / 2
        return (f"M{x1:g} {y - 0.4:g} L{x2:g} {y - h:g} A{h:g} {h:g} 0 0 1 {x2:g} {y + h:g} "
                f"L{x1:g} {y + 0.4:g} Z")

    def render(self, ring, trail, spark=None, glass=None, glint=None, inner=None):
        cx, cy, r, w = self.ring
        out = [f'<g transform="rotate({self.angle:g} {PIVOT[0]:g} {PIVOT[1]:g})">']
        for g_ in glass or []:
            out.append(f'<circle cx="{cx:g}" cy="{cy:g}" r="{r - w / 2 + 0.3:g}" fill="{g_}"/>')
        if inner:
            # thin inner glow just inside the ring
            out.append(f'<circle cx="{cx:g}" cy="{cy:g}" r="{r - w / 2 - 0.9:g}" fill="none" '
                       f'stroke="{inner}" stroke-width="1.6"/>')
        out.append(f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="none" stroke="{ring}" '
                   f'stroke-width="{w:g}"/>')
        for x1, y, x2, tw in self.trails:
            out.append(f'<path d="{self.trail_path(x1, y, x2, tw)}" fill="{trail}"/>')
        out.append("</g>")
        if glint:
            # crisp specular arc, upper-left inside the lens (unrotated: light from above)
            ccx, ccy = self.rot(cx, cy)
            gr = r - w / 2 - 3.0
            a0, a1 = math.radians(195), math.radians(255)
            out.append(f'<path d="M{ccx + gr * math.cos(a0):.2f} {ccy + gr * math.sin(a0):.2f} '
                       f'A{gr:g} {gr:g} 0 0 1 {ccx + gr * math.cos(a1):.2f} {ccy + gr * math.sin(a1):.2f}" '
                       f'fill="none" stroke="{glint}" stroke-width="2.4" stroke-linecap="round"/>')
        if self.spark and spark:
            px, py, s = self.spark_pos()
            k = s * 0.22
            out.append(f'<path d="M{px:.2f} {py - s:.2f} Q{px + k:.2f} {py - k:.2f} {px + s:.2f} {py:.2f} '
                       f'Q{px + k:.2f} {py + k:.2f} {px:.2f} {py + s:.2f} Q{px - k:.2f} {py + k:.2f} '
                       f'{px - s:.2f} {py:.2f} Q{px - k:.2f} {py - k:.2f} {px:.2f} {py - s:.2f}Z" '
                       f'fill="{spark}"/>')
        return "".join(out)


COMET = Glyph()
# Hinted for 16-32 px: two chunkier trails, thicker ring, bigger spark.
COMET_SMALL = Glyph(ring=(62.0, 50.0, 18.0, 10.5), trails=((12, 40, 34, 11), (18, 61, 35, 11)),
                    spark=(17.0, -17.0, 7.5))
# Menu bar template glyphs.
COMET_MENU_2X = Glyph(ring=(62.0, 50.0, 18.0, 9.0),
                      trails=((16, 36, 37, 9), (6, 50, 35, 9), (20, 64, 37, 9)),
                      spark=(23.5, -23.5, 6.0))  # detached from the ring: no merging in mono
COMET_MENU_1X = Glyph(ring=(62.0, 50.0, 18.0, 11.0), trails=((12, 40, 32, 12), (18, 61, 33, 12)),
                      spark=(25.0, -25.0, 7.5))


# ---------------------------------------------------------------- helpers
def lin(gid, stops, x1=0, y1=0, x2=0, y2=1, user=False):
    u = ' gradientUnits="userSpaceOnUse"' if user else ""
    s = "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a}"' if a is not None else "") + "/>"
                for o, c, a in stops)
    return f'<linearGradient id="{gid}"{u} x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>'


def radial(gid, cx, cy, r, stops, user=True):
    u = ' gradientUnits="userSpaceOnUse"' if user else ""
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{gid}"{u} cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'


def ring_gradient(gid, end):
    return lin(gid, [(0, ORANGE, None), (0.5, PINK, None), (1, end, None)], 38, 72, 86, 28, user=True)


def trail_gradient(gid, tail=TRAIL_TAIL, head=TRAIL_HEAD):
    return lin(gid, [(0, tail, 0), (0.5, "#FFA040", 0.9), (1, head, None)], 4, 0, 40, 0, user=True)


def glass_defs(prefix=""):
    """Lens glass: an opaque cool base so nothing behind muddies it, then a
    lighter cool sheen from the upper-left."""
    return (radial(f"{prefix}glassbase", 62, 50, 16,
                   [(0, "#5D67A8", 1), (0.7, "#454C82", 1), (1, "#3A406E", 1)])
            + radial(f"{prefix}glass", 55, 42, 17,
                     [(0, "#E6ECFF", 0.55), (0.55, "#C2CCFF", 0.18), (1, "#C2CCFF", 0.04)]))


# ---------------------------------------------------------------- squircle
def squircle(x, y, w, h, r):
    """Continuous-corner rounded rect (the iOS/macOS 'squircle' curve)."""
    r = min(r, min(w, h) / 2 / 1.52866483)
    X0, Y0, X1, Y1 = x, y, x + w, y + h

    def tr(a, b): return (X1 - a * r, Y0 + b * r)
    def br(a, b): return (X1 - b * r, Y1 - a * r)
    def bl(a, b): return (X0 + a * r, Y1 - b * r)
    def tl(a, b): return (X0 + b * r, Y0 + a * r)

    corner = [
        ("L", [(1.52866471, 0.0)]),
        ("C", [(1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)]),
        ("L", [(0.63149399, 0.07491100)]),
        ("C", [(0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491176, 0.63149399)]),
        ("C", [(0.0, 0.86840701), (0.0, 1.08849299), (0.0, 1.52866483)]),
    ]
    f = lambda p: f"{p[0]:.2f} {p[1]:.2f}"
    d = [f"M{f(tl(0, 1.52866483))}"]
    for fn in (tr, br, bl, tl):
        for cmd, pts in corner:
            d.append(cmd + " ".join(f(fn(*p)) for p in pts))
    d.append("Z")
    return " ".join(d)


BODY = squircle(100, 100, 824, 824, 185.4)


# ---------------------------------------------------------------- wordmark
def wordmark_paths(font_path, text="Fastlight", weight=600, tracking=-12):
    """Outline `text` with Sora at the given weight; returns (d, advance, upm)."""
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen

    font = instantiateVariableFont(TTFont(font_path), {"wght": weight})
    cmap = font.getBestCmap()
    gs = font.getGlyphSet()
    hmtx = font["hmtx"]
    upm = font["head"].unitsPerEm
    pen = SVGPathPen(gs)
    x = 0
    for ch in text:
        name = cmap[ord(ch)]
        # flip Y: font units are y-up, SVG is y-down; baseline at y=0
        gs[name].draw(TransformPen(pen, (1, 0, 0, -1, x, 0)))
        x += hmtx[name][0] + tracking
    return pen.getCommands(), x - tracking, upm


# ---------------------------------------------------------------- documents
def svg(w, h, body, view=None, title=None):
    view = view or f"0 0 {w} {h}"
    t = f"<title>{title}</title>" if title else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="{view}">{t}{body}</svg>\n')


def place(g, scale, at=(512, 512)):
    cx, cy = g.centre()
    return f"translate({at[0]:g} {at[1]:g}) scale({scale:g}) translate({-cx:.3f} {-cy:.3f})"


def to_px(g, scale, x, y, at=(512, 512)):
    cx, cy = g.centre()
    return at[0] + (x - cx) * scale, at[1] + (y - cy) * scale


def app_icon():
    """1024 canvas, 824 body (macOS grid), continuous corners, graphite tile."""
    scale = 7.3
    lx, ly = to_px(COMET, scale, *COMET.rot(62, 50))
    defs = (
        lin("bg", [(0, GRAPHITE_700, None), (1, GRAPHITE_950, None)])
        + radial("halo", f"{lx:.0f}", f"{ly:.0f}", 400,
                 [(0, PINK, 0.42), (0.5, VIOLET, 0.18), (1, VIOLET, 0)])
        + lin("rim", [(0, "#FFFFFF", 0.45), (0.2, "#FFFFFF", 0.08), (1, "#FFFFFF", 0.04)])
        + ring_gradient("ring", LAVENDER) + trail_gradient("tr") + glass_defs()
        + '<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">'
          '<feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.3"/></filter>'
          '<filter id="bloom" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="2.6"/></filter>'
          '<filter id="grain" x="0" y="0" width="100%" height="100%">'
          '<feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="7"/>'
          '<feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 0.05 0"/></filter>'
        + f'<clipPath id="clip"><path d="{BODY}"/></clipPath>'
    )
    tf = place(COMET, scale)
    bloom = COMET.render(PINK, TRAIL_TAIL, spark="#FFE07A")
    glyph = COMET.render("url(#ring)", "url(#tr)", spark=SPARK,
                         glass=["url(#glassbase)", "url(#glass)"], glint="#FFFFFF",
                         inner="#C9C2FF66")
    full = '<rect x="100" y="100" width="824" height="824" fill="url(#{})"/>'
    body = (
        f'<g filter="url(#shadow)"><path d="{BODY}" fill="url(#bg)"/></g>'
        f'<g clip-path="url(#clip)">{full.format("halo")}'
        f'<rect x="100" y="100" width="824" height="824" filter="url(#grain)"/></g>'
        f'<path d="{BODY}" fill="none" stroke="url(#rim)" stroke-width="4"/>'
        f'<g transform="{tf}"><g filter="url(#bloom)" opacity="0.5">{bloom}</g>{glyph}</g>'
    )
    return svg(1024, 1024, f"<defs>{defs}</defs>{body}", title="Fastlight")


def app_icon_small():
    """Flat, hinted icon for the 16 and 32 px slots."""
    defs = (lin("bg", [(0, GRAPHITE_700, None), (1, "#17181D", None)])
            + ring_gradient("ring", LAVENDER))
    g = COMET_SMALL.render("url(#ring)", "#FFA040", spark=SPARK, glass=["#4A5288"])
    return svg(1024, 1024, f'<defs>{defs}</defs><path d="{BODY}" fill="url(#bg)"/>'
                           f'<g transform="{place(COMET_SMALL, 8.3)}">{g}</g>', title="Fastlight")


def mark_body(on_dark, g=COMET, prefix="m"):
    """The comet on a transparent background."""
    ring = ring_gradient(f"{prefix}ring", LAVENDER if on_dark else VIOLET)
    tr = trail_gradient(f"{prefix}tr")
    defs = ring + tr
    glass = None
    glint = None
    if on_dark:
        defs += glass_defs(prefix)
        glass = [f"url(#{prefix}glassbase)", f"url(#{prefix}glass)"]
        glint = "#FFFFFF"
    return defs, g.render(f"url(#{prefix}ring)", f"url(#{prefix}tr)",
                          spark=SPARK if on_dark else SPARK_LIGHT, glass=glass, glint=glint)


def view_of(g, pad=0.5, square=False, extra=0.0):
    bx, by, bw, bh = g.bounds()
    if square:
        side = max(bw, bh) + extra
        cx, cy = bx + bw / 2, by + bh / 2
        return cx - side / 2, cy - side / 2, side, side
    return bx - pad, by - pad, bw + 2 * pad, bh + 2 * pad


def mark(on_dark=False, square=False):
    vx, vy, vw, vh = view_of(COMET, square=square, extra=10)
    defs, body = mark_body(on_dark)
    return svg(round(vw * 10), round(vh * 10), f"<defs>{defs}</defs>{body}",
               view=f"{vx:.3f} {vy:.3f} {vw:.3f} {vh:.3f}", title="Fastlight")


def favicon():
    """Rounded graphite tile with the hinted comet; reads on light and dark tabs."""
    defs = ring_gradient("ring", LAVENDER)
    g = COMET_SMALL.render("url(#ring)", "#FFA040", spark=SPARK, glass=["#4A5288"])
    _, _, bw, bh = COMET_SMALL.bounds()
    k = 86 / max(bw, bh)
    return svg(64, 64, f'<defs>{defs}</defs><rect width="100" height="100" rx="22" fill="{GRAPHITE_900}"/>'
                       f'<g transform="{place(COMET_SMALL, k, (50, 50))}">{g}</g>',
               view="0 0 100 100", title="Fastlight")


def apple_touch():
    """Full-bleed square (iOS applies its own mask)."""
    lx, ly = to_px(COMET, 0.66, *COMET.rot(62, 50), at=(50, 50))
    defs, body = mark_body(True)
    defs += (lin("bg", [(0, GRAPHITE_700, None), (1, GRAPHITE_950, None)])
             + radial("halo", f"{lx:.1f}", f"{ly:.1f}", 42,
                      [(0, PINK, 0.4), (0.5, VIOLET, 0.16), (1, VIOLET, 0)]))
    return svg(180, 180, f'<defs>{defs}</defs><rect width="100" height="100" fill="url(#bg)"/>'
                         f'<rect width="100" height="100" fill="url(#halo)"/>'
                         f'<g transform="{place(COMET, 0.66, (50, 50))}">{body}</g>',
               view="0 0 100 100", title="Fastlight")


def menubar(size):
    """Template image: black on transparent (alpha only), fitted to the canvas."""
    g = COMET_MENU_1X if size <= 18 else COMET_MENU_2X
    vx, vy, vw, vh = view_of(g, square=True)
    side = vw * 1.06
    vx -= (side - vw) / 2
    vy -= (side - vh) / 2
    return svg(size, size, g.render("#000", "#000", spark="#000"),
               view=f"{vx:.3f} {vy:.3f} {side:.3f} {side:.3f}")


def lockup(font_path, on_dark=False):
    """Mark + outlined wordmark. Cap height = 0.62 x lens diameter, caps
    centred on the lens; gap between mark and wordmark = 0.3 x lens."""
    d, adv, _ = wordmark_paths(font_path)
    cx, cy, r, w = COMET.ring
    lens = 2 * r + w
    cap = 730
    s = 0.62 * lens / cap
    mx, my, mw, mh = view_of(COMET)
    tx = mx + mw + 0.3 * lens
    _, lcy = COMET.rot(cx, cy)
    baseline = lcy + cap * s / 2
    asc, desc = 760 * s, 235 * s  # Sora ascender of l/h, descender of g
    top = min(my, baseline - asc) - 1
    bottom = max(my + mh, baseline + desc) + 1
    width = tx + adv * s - mx + 1
    defs, body = mark_body(on_dark)
    text = FOG if on_dark else GRAPHITE_900
    body += f'<path fill="{text}" transform="translate({tx:.3f} {baseline:.3f}) scale({s:.6f})" d="{d}"/>'
    vh = bottom - top
    return svg(round(width * 8), round(vh * 8), f"<defs>{defs}</defs>{body}",
               view=f"{mx:.3f} {top:.3f} {width:.3f} {vh:.3f}", title="Fastlight")


def wordmark(font_path, on_dark=False):
    d, adv, _ = wordmark_paths(font_path)
    fill = FOG if on_dark else GRAPHITE_900
    # descender of 'g' ~ -230, ascender of 'F/l/h/t' ~ 760
    return svg(round(adv / 4), 250,
               f'<path fill="{fill}" transform="translate(0 790)" d="{d}"/>',
               view=f"0 0 {adv} 1000", title="Fastlight")


# ---------------------------------------------------------------- DMG window
# The DMG window, in points (the background is rendered at 1x and 2x). These
# numbers must match scripts/dmg-settings.py: icons are centred on DMG_APP and
# DMG_APPS, and Finder draws their labels below them in black, whatever the
# appearance, so everything under the icons stays light.
DMG_W, DMG_H = 660, 400
DMG_SLACK = 20  # extra plain canvas below, in case the title bar is shorter than expected
DMG_APP, DMG_APPS = (170, 200), (490, 200)
DMG_ICON = 128


def shaped_paths(font_path, text, size, weight, tracking=0.0, opsz=None):
    """Outline `text`, shaped with HarfBuzz (kerning), at `size` px; returns
    (d, width) with the baseline at y=0, in px."""
    import io

    import uharfbuzz as hb
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont

    font = TTFont(font_path)
    axes = {a.axisTag for a in font["fvar"].axes}
    loc = {"wght": weight}
    if "opsz" in axes:
        loc["opsz"] = opsz or size
    font = instantiateVariableFont(font, loc)
    buf = io.BytesIO()
    font.save(buf)
    hbfont = hb.Font(hb.Face(hb.Blob(buf.getvalue())))
    upm = font["head"].unitsPerEm
    hb_buf = hb.Buffer()
    hb_buf.add_str(text)
    hb_buf.guess_segment_properties()
    hb.shape(hbfont, hb_buf, {"kern": True, "liga": True})
    order = font.getGlyphOrder()
    gs = font.getGlyphSet()
    k = size / upm
    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.2f}")
    x = 0.0
    for info, pos in zip(hb_buf.glyph_infos, hb_buf.glyph_positions):
        gs[order[info.codepoint]].draw(
            TransformPen(pen, (k, 0, 0, -k, x + pos.x_offset * k, -pos.y_offset * k)))
        x += pos.x_advance * k + tracking
    return pen.getCommands(), x - tracking


def dmg_arrow(x1, x2, y):
    """A comet tail: needle-thin on the left, swelling towards a rounded
    chevron head on the right, orange -> pink -> violet."""
    head = 10.0   # chevron half-height
    w = 4.5       # tail width at the head, and chevron stroke
    tail_end = x2 - 5
    tail = (f"M{x1:g} {y - 0.4:g} L{tail_end:g} {y - w / 2:g} "
            f"A{w / 2:g} {w / 2:g} 0 0 1 {tail_end:g} {y + w / 2:g} L{x1:g} {y + 0.4:g} Z")
    chevron = f"M{x2 - head:g} {y - head:g} L{x2:g} {y:g} L{x2 - head:g} {y + head:g}"
    return (f'<path d="{tail}" fill="url(#arrow)"/>'
            f'<path d="{chevron}" fill="none" stroke="url(#arrowhead)" stroke-width="{w:g}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def dmg_hint(inter, cx, baseline):
    """'Then open it and press [⌥] [Space] to search.', centred on cx."""
    size, pad, gap, cap_h = 14, 7, 6, 22
    parts = [("text", "Then open it and press"), ("key", "\u2325"), ("key", "Space"),
             ("text", "to search.")]
    shaped = []
    for kind, text in parts:
        d, w = shaped_paths(inter, text, size if kind == "text" else 13, 400 if kind == "text" else 500)
        box = w + 2 * pad if kind == "key" else w
        shaped.append((kind, d, w, max(box, cap_h)))
    space = 0.3 * size
    total = sum(b for _, _, _, b in shaped) + space * (len(shaped) - 1) - (gap - space)
    x = cx - total / 2
    out = []
    for i, (kind, d, w, box) in enumerate(shaped):
        if kind == "key":
            top = baseline - 15.5
            out.append(f'<rect x="{x:.2f}" y="{top + 1:.2f}" width="{box:.2f}" height="{cap_h}" rx="5" '
                       f'fill="#E3E3E9"/>'
                       f'<rect x="{x:.2f}" y="{top:.2f}" width="{box:.2f}" height="{cap_h}" rx="5" '
                       f'fill="#FFFFFF" stroke="#DCDCE3" stroke-width="1"/>'
                       f'<path fill="{GRAPHITE_900}" transform="translate({x + (box - w) / 2:.2f} {baseline - 0.5:.2f})" d="{d}"/>')
        else:
            out.append(f'<path fill="{GRAPHITE_500}" transform="translate({x:.2f} {baseline:.2f})" d="{d}"/>')
        x += box
        if i + 1 < len(shaped):
            both_keys = kind == "key" and shaped[i + 1][0] == "key"
            x += gap if both_keys else space
    return "".join(out)


def dmg_background(sora, inter):
    """Paper background with a soft comet glow, a headline, a comet-tail arrow
    from the app to Applications and a hint about the hotkey."""
    W, H = DMG_W, DMG_H + DMG_SLACK
    (ax, ay), (bx, by) = DMG_APP, DMG_APPS
    mid = (ax + bx) / 2
    # The app tile fills 824/1024 of its icon, the Applications folder about
    # 0.92: leave the same space between the arrow and each visible edge.
    x1 = ax + DMG_ICON * 824 / 2048 + 32
    x2 = bx - DMG_ICON * 0.46 - 32
    defs = (
        lin("arrow", [(0, TRAIL_TAIL, 0), (0.45, ORANGE, 0.9), (1, PINK, None)],
            x1, 0, x2, 0, user=True)
        + lin("arrowhead", [(0, PINK, None), (1, VIOLET, None)], x2 - 10, 0, x2, 0, user=True)
        + radial("glow", mid, ay, 300, [(0, PINK, 0.10), (0.45, VIOLET, 0.05), (1, VIOLET, 0)])
        + radial("warm", ax, ay + 40, 220, [(0, ORANGE, 0.07), (1, ORANGE, 0)])
    )
    title, tw = shaped_paths(sora, "Drag Fastlight to Applications", 24, 600, tracking=-0.3)
    body = (
        f'<rect width="{W}" height="{H}" fill="#FAFAFB"/>'
        f'<rect width="{W}" height="{H}" fill="url(#warm)"/>'
        f'<rect width="{W}" height="{H}" fill="url(#glow)"/>'
        f'<path fill="{GRAPHITE_900}" transform="translate({mid - tw / 2:.2f} 78)" d="{title}"/>'
        + dmg_arrow(x1, x2, ay)
        + dmg_hint(inter, mid, 350)
    )
    return svg(W, H, f"<defs>{defs}</defs>{body}", title="Fastlight installer")


def main():
    font, out, inter = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    src = out / "src"
    src.mkdir(parents=True, exist_ok=True)
    files = {
        out / "app-icon.svg": app_icon(),
        src / "app-icon-small.svg": app_icon_small(),
        out / "logo-mark.svg": mark(),
        out / "logo-mark-dark.svg": mark(on_dark=True),
        src / "mark-square.svg": mark(square=True),
        src / "mark-square-dark.svg": mark(on_dark=True, square=True),
        src / "apple-touch-icon.svg": apple_touch(),
        out / "favicon.svg": favicon(),
        out / "logo-lockup.svg": lockup(font),
        out / "logo-lockup-dark.svg": lockup(font, on_dark=True),
        out / "wordmark.svg": wordmark(font),
        out / "wordmark-dark.svg": wordmark(font, on_dark=True),
        src / "menubar-18.svg": menubar(18),
        src / "menubar-36.svg": menubar(36),
        src / "dmg-background.svg": dmg_background(font, inter),
    }
    for p, content in files.items():
        p.write_text(content)
        print("wrote", p)


if __name__ == "__main__":
    main()
