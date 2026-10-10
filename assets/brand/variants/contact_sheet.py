#!/usr/bin/env python3
"""Render variants and build a comparison sheet in build/brand-review/ (needs resvg)."""
import base64
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "build" / "brand-review"
tmp = Path(tempfile.mkdtemp())


def render(src, size, name):
    p = tmp / f"{name}-{size}.png"
    subprocess.run(["resvg", "-w", str(size), "-h", str(size), str(src), str(p)], check=True)
    return base64.b64encode(p.read_bytes()).decode()


def img(data, x, y, w, pixel=False):
    st = ' style="image-rendering:pixelated"' if pixel else ""
    return f'<image x="{x}" y="{y}" width="{w}" height="{w}"{st} href="data:image/png;base64,{data}"/>'


def build(COLS, outname):
    OUT.mkdir(parents=True, exist_ok=True)
    COLW, PANEL_H = 360, 620
    parts = []
    for row, (bg, fg, sub, menubar_bg) in enumerate((("#F2F2F5", "#1A1A1F", "#6B6B76", "#F6F6F8"),
                                                     ("#1C1C20", "#F2F2F5", "#9A9AA6", "#2A2A30"))):
        y0 = row * PANEL_H
        parts.append(f'<rect x="0" y="{y0}" width="{COLW * len(COLS)}" height="{PANEL_H}" fill="{bg}"/>')
        parts.append(f'<text x="16" y="{y0 + 30}" font-family="Helvetica" font-size="15" fill="{sub}">'
                     f'{"Light background" if row == 0 else "Dark background"}</text>')
        for i, (label, big, small, mb2, mb1) in enumerate(COLS):
            x = i * COLW + 20
            tag = f"{i}"
            parts.append(f'<text x="{x}" y="{y0 + 62}" font-family="Helvetica" font-weight="bold" '
                         f'font-size="22" fill="{fg}">{label}</text>')
            parts.append(img(render(big, 1024, tag + "b"), x, y0 + 80, 300))  # 1024 render shown at 300
            parts.append(img(render(big, 128, tag + "b"), x, y0 + 400, 128))
            parts.append(img(render(small, 32, tag + "s"), x + 148, y0 + 400, 32))
            parts.append(img(render(small, 16, tag + "s"), x + 196, y0 + 408, 16))
            parts.append(img(render(small, 16, tag + "s"), x + 148, y0 + 448, 80, pixel=True))
            # menu bar strip
            parts.append(f'<rect x="{x}" y="{y0 + 545}" width="300" height="26" rx="6" fill="{menubar_bg}"/>')
            m2 = render(mb2, 36, tag + "m")
            m1 = render(mb1, 18, tag + "m")
            # template images are black; on dark menu bars macOS inverts them -> simulate
            inv = ' filter="url(#inv)"' if row == 1 else ""
            parts.append(f'<g{inv}>{img(m2, x + 12, y0 + 549, 18)}{img(m1, x + 42, y0 + 549, 18)}'
                         f'{img(m2, x + 240, y0 + 540 - 0, 36)}</g>')
            parts.append(f'<text x="{x + 72}" y="{y0 + 563}" font-family="Helvetica" font-size="11" fill="{sub}">'
                         f'menu bar 2x · 1x · zoom</text>')
            parts.append(f'<text x="{x + 148}" y="{y0 + 545 - 12}" font-family="Helvetica" font-size="11" '
                         f'fill="{sub}">128 · 32 · 16 (16 zoomed)</text>')

    W, H = COLW * len(COLS), PANEL_H * 2
    sheet = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">'
             '<defs><filter id="inv"><feColorMatrix values="-1 0 0 0 1  0 -1 0 0 1  0 0 -1 0 1  0 0 0 1 0"/></filter></defs>'
             + "".join(parts) + "</svg>")
    (tmp / "sheet.svg").write_text(sheet)
    subprocess.run(["resvg", str(tmp / "sheet.svg"), str(OUT / outname)], check=True)
    print(OUT / outname)


if __name__ == "__main__":
    cols = [("Current", ROOT / "assets/brand/app-icon.svg", ROOT / "assets/brand/src/app-icon-small.svg",
             ROOT / "assets/brand/src/menubar-36.svg", ROOT / "assets/brand/src/menubar-18.svg")]
    for key, label in (("a-daylight", "A · Daylight"), ("b-sunrise", "B · Sunrise"), ("c-comet", "C · Comet")):
        cols.append((label, HERE / f"{key}-app-icon.svg", HERE / f"{key}-app-icon-small.svg",
                     HERE / f"{key}-menubar-36.svg", HERE / f"{key}-menubar-18.svg"))
    build(cols, "variants.png")
