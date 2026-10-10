#!/usr/bin/env python3
"""The Comet mark (variant C) on different background tiles.

Writes comet-bg-<key>-*.svg next to this file and builds
build/brand-review/comet-backgrounds.png. Needs resvg.
"""
from contact_sheet import build
from generate_variants import BODY, HERE, Glyph, icon, lin, tile

# Comet geometry: identical for every background.
G = Glyph(angle=-30, ring=(62, 50, 18, 7.5),
          trails=((14, 37, 38, 8), (4, 50, 36, 8), (18, 63, 38, 8)),
          taper=True, spark=(17, -17, 6.5))
GS = Glyph(angle=-30, ring=(62, 50, 18, 10.5), trails=((12, 40, 34, 11), (18, 61, 35, 11)),
           taper=True, spark=(17, -17, 7))

FULL = "<rect x=\"100\" y=\"100\" width=\"824\" height=\"824\" fill=\"url(#{})\"/>"


def radial(gid, cx, cy, r, stops):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'


# key, label, background defs (must define #bg, optionally #halo), small-tile bg stops,
# ring stops (orange -> pink -> X), trail stops, spark colour
BACKGROUNDS = [
    ("night", "Night",
     lin("bg", [(0, "#3A2FD9", None), (0.55, "#2A1F9E", None), (1, "#160F5C", None)], 0.2, 0, 0.8, 1)
     + radial("halo", 610, 450, 430, [(0, "#6A5CFF", 0.65), (1, "#6A5CFF", 0)]),
     [(0, "#3A2FD9", None), (1, "#1A1270", None)],
     ["#FF9A3D", "#FF5C9A", "#C3B4FF"]),
    ("violet", "Violet",
     lin("bg", [(0, "#9A4DFF", None), (0.5, "#6B2EE6", None), (1, "#3D139E", None)], 0, 0, 1, 1)
     + radial("halo", 610, 450, 420, [(0, "#FF8AD8", 0.35), (1, "#FF8AD8", 0)]),
     [(0, "#9A4DFF", None), (1, "#4A18B0", None)],
     ["#FFA23D", "#FF5C9A", "#FFD0EC"]),
    ("teal", "Midnight teal",
     lin("bg", [(0, "#13C2C2", None), (0.5, "#1468A8", None), (1, "#0F1F66", None)], 1, 0, 0, 1)
     + radial("halo", 610, 450, 420, [(0, "#7DF5FF", 0.30), (1, "#7DF5FF", 0)]),
     [(0, "#13B5C2", None), (1, "#12307A", None)],
     ["#FFA23D", "#FF5C9A", "#C9B8FF"]),
    ("plum", "Plum",
     lin("bg", [(0, "#D6338F", None), (0.5, "#8E1F7A", None), (1, "#3E0F55", None)], 0.9, 0, 0.1, 1)
     + radial("halo", 610, 450, 420, [(0, "#FFB0D8", 0.30), (1, "#FFB0D8", 0)]),
     [(0, "#C42E8C", None), (1, "#4A1260", None)],
     ["#FFB23D", "#FFE08A", "#FFFFFF"]),
    ("graphite", "Graphite glow",
     lin("bg", [(0, "#34353F", None), (1, "#15161B", None)])
     + radial("halo", 600, 450, 400, [(0, "#FF5C9A", 0.42), (0.5, "#7B5CFF", 0.18), (1, "#7B5CFF", 0)]),
     [(0, "#34353F", None), (1, "#17181D", None)],
     ["#FF9A3D", "#FF5C9A", "#A88BFF"]),
    ("sky", "Daylight blue",
     lin("bg", [(0, "#38C6FF", None), (0.55, "#2F86FF", None), (1, "#3B4BF0", None)], 0, 0, 1, 1)
     + radial("halo", 610, 440, 420, [(0, "#FFFFFF", 0.35), (1, "#FFFFFF", 0)]),
     [(0, "#38C6FF", None), (1, "#3B55F0", None)],
     ["#FFA23D", "#FF4F8B", "#6A3DFF"]),
]

TRAIL = [(0, "#FFB13B", 0), (0.5, "#FFA040", 0.9), (1, "#FF7A50", None)]
SPARK = "#FFC81A"


def make(key, bg_defs, small_stops, ring):
    ring_g = lin("ring", [(0, ring[0], None), (0.5, ring[1], None), (1, ring[2], None)],
                 38, 72, 86, 28, user=True)
    defs = (bg_defs + ring_g + lin("tr", TRAIL, 4, 0, 40, 0, user=True)
            + '<radialGradient id="glass" gradientUnits="userSpaceOnUse" cx="56" cy="44" r="14">'
              # translucent glass: the tile shows through, so it reads as a lens, not a ball
              '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.42"/>'
              '<stop offset="1" stop-color="#FFE3EC" stop-opacity="0.14"/></radialGradient>')
    place = G.place(7.3)
    glyph = (f'<g transform="{place}">'
             + G.render("url(#ring)", "url(#tr)", glass="url(#glass)", glint="#FFFFFF", spark_paint=SPARK)
             + "</g>")
    bloom = f'<g transform="{place}" opacity="0.5">' + G.render(ring[1], "#FFB13B", spark_paint="#FFE07A") + "</g>"
    layers = FULL.format("bg") + (FULL.format("halo") if 'id="halo"' in bg_defs else "")
    big = icon(defs, layers, glyph, bloom)
    small = tile(lin("bg", small_stops, 0, 0, 1, 1) + ring_g, "url(#bg)",
                 f'<g transform="{GS.place(8.3)}">'
                 + GS.render("url(#ring)", "#FFA040", glass="#FFFFFF4D", spark_paint=SPARK) + "</g>")
    for name, content in (("app-icon", big), ("app-icon-small", small)):
        (HERE / f"comet-bg-{key}-{name}.svg").write_text(content)


def main():
    cols = []
    for key, label, bg_defs, small_stops, ring in BACKGROUNDS:
        make(key, bg_defs, small_stops, ring)
        # menu-bar glyph is the same for every background (template image)
        cols.append((label, HERE / f"comet-bg-{key}-app-icon.svg", HERE / f"comet-bg-{key}-app-icon-small.svg",
                     HERE / "c-comet-menubar-36.svg", HERE / "c-comet-menubar-18.svg"))
    print(build(cols, "comet-backgrounds.png") or "built")


if __name__ == "__main__":
    main()
