# Fastlight brand

Fastlight is a fast, Spotlight-style launcher for macOS, powered by fsearch.
The brand says three things: **it is instant**, **it finds things**, and **it
is a joy to use**. The look is a dark graphite base with one burst of warm,
colourful light.

## The mark: "Comet"

A glass lens launches up and to the right at 30°. It trails three tapered comet
tails, and a gold spark sits at its leading edge.

- **The lens means search.** It is the part of a magnifier everyone
  recognises, but it has **no handle**, so it never copies Apple's Spotlight
  glyph or a stock magnifier. The ring runs **orange → pink → violet**.
- **The comet tails mean speed and light** (the "light" in Fast*light*). They
  taper from a needle point into a round head, and they clearly rise, so the
  motion reads as launching, not drooping.
- **The gold spark** is the moment a result is found. It gives the mark its
  optimism.
- **The graphite tile** keeps the app icon calm next to other macOS icons. A
  soft pink/violet glow behind the lens keeps it from feeling gloomy.

The geometry lives in `src/generate.py`, on a 100-unit grid:

- Lens: radius 18, stroke 7.5.
- Trails: three tapered tails, 8 units wide at the head. The middle one is
  the longest.
- Rotation: −30°.

At 16–32 px a **hinted variant** takes over: two chunkier tails, a thicker
ring and a bigger spark. It is used for the app icon's 16/32 slots, the
favicon and the 1x menu bar icon.

## Palette

Graphite takes up most of the space (60%). The comet gradient is the brand
colour (30%), and gold is the spark (10%, used sparingly).

### Core

| Token | Hex | Use |
|---|---|---|
| `graphite-950` | `#15161B` | Dark-mode page background, icon tile bottom |
| `graphite-900` | `#1E1F25` | Dark surfaces; **logo wordmark and text on light** |
| `graphite-800` | `#2A2B33` | Raised cards in dark mode |
| `graphite-700` | `#34353F` | Borders in dark mode, icon tile top |
| `graphite-500` | `#5C5E6B` | Secondary text on light (6.2:1 on paper) |
| `graphite-300` | `#A3A5B3` | Secondary text on dark (7.4:1 on graphite-950) |
| `paper` | `#FAFAFB` | Light-mode page background |
| `fog` | `#F5F3EE` | Primary text and wordmark on dark (16.3:1) |

### Comet (brand gradient)

| Token | Hex | Use |
|---|---|---|
| `comet-orange` | `#FF9A3D` | Ring start, trail heads |
| `comet-pink` | `#FF5C9A` | Ring middle, glow |
| `comet-violet` | `#7B5CFF` | Ring end on light backgrounds (graphic only, 4.2:1) |
| `comet-lavender` | `#A88BFF` | Ring end on dark backgrounds; link text on dark (6.7:1) |
| `trail-tail` → `trail-head` | `#FFB13B` → `#FF7A50` | Tapered tails (fade to 0 opacity at the tail) |
| `spark` | `#FFC81A` | Gold spark on dark (11.6:1 on graphite-950) |
| `spark-deep` | `#F5A300` | Spark on light backgrounds (graphic only) |
| `lens-glass` | `#5D67A8` → `#3A406E` | Lens fill on dark: cool glass with a `#E6ECFF` sheen |

Brand gradient, for CSS:

```css
--comet: linear-gradient(135deg, #FF9A3D 0%, #FF5C9A 50%, #7B5CFF 100%);       /* on light */
--comet-dark: linear-gradient(135deg, #FF9A3D 0%, #FF5C9A 50%, #A88BFF 100%);  /* on dark  */
```

### Text-safe accents

Body-size text needs at least 4.5:1:

| Role | Light page (`paper`) | Dark page (`graphite-950`) |
|---|---|---|
| Link | `#6A3DF0` violet (5.7:1) | `#A88BFF` lavender (6.7:1) |
| Accent / highlight text | `#C21E63` deep pink (5.5:1) | `#FF5C9A` pink (6.2:1) |
| Warm accent text | `#B24A00` (5.2:1) | `#FF9A3D` orange (8.6:1) |

Never set body text in `#FF9A3D`, `#FF5C9A` or `#7B5CFF` on light backgrounds.

### Light / dark mapping for the website

| Role | Light | Dark |
|---|---|---|
| Page background | `paper #FAFAFB` | `graphite-950 #15161B` |
| Surface / card | `#FFFFFF` | `graphite-900 #1E1F25` |
| Border | `#E7E7EC` | `graphite-700 #34353F` |
| Primary text | `graphite-900 #1E1F25` (15.8:1) | `fog #F5F3EE` (16.3:1) |
| Secondary text | `graphite-500 #5C5E6B` | `graphite-300 #A3A5B3` |
| Link | `#6A3DF0` | `#A88BFF` |
| Primary button | `--comet` gradient bg, `#FFFFFF` text, weight 600 (white on the violet end is 5.9:1, on the pink middle about 3:1, so keep labels ≥ 17 px semibold) or solid `graphite-900` with `fog` text | Solid `#FF9A3D` bg with `graphite-950` text (8.6:1), or `--comet-dark` bg with `graphite-950` text |
| Code block bg | `#F1F1F4` | `#1A1B21` |
| Focus ring | `#7B5CFF` 2 px | `#A88BFF` 2 px |

**Hero:** dark even in light mode. Use a `graphite-950` background with a
radial glow behind the app icon or a screenshot:
`radial-gradient(circle at 60% 45%, rgba(255,92,154,.35), rgba(123,92,255,.15) 40%, transparent 70%)`.
That is the same lighting as the icon. Use the comet gradient for at most one
headline word or one button per screen.

```css
:root {
  --graphite-950:#15161B; --graphite-900:#1E1F25; --graphite-800:#2A2B33; --graphite-700:#34353F;
  --graphite-500:#5C5E6B; --graphite-300:#A3A5B3; --paper:#FAFAFB; --fog:#F5F3EE;
  --comet-orange:#FF9A3D; --comet-pink:#FF5C9A; --comet-violet:#7B5CFF; --comet-lavender:#A88BFF;
  --spark:#FFC81A; --spark-deep:#F5A300;
  --link-light:#6A3DF0; --accent-light:#C21E63; --warm-light:#B24A00;
}
```

## Typography (website)

| Role | Font | Weights | Notes |
|---|---|---|---|
| Display / headings | **Sora** (Google Fonts) | 600, 700 | The wordmark is Sora SemiBold, so headings echo the logo. Use letter-spacing `-0.02em` at 37 px and up. |
| Body / UI | **Inter** (Google Fonts) | 400, 500 | Line-height 1.6. |
| Code / query examples / keys | **JetBrains Mono** (Google Fonts) | 400, 500 | For `ext:pdf mtime:<30d`, ⌥Space key caps and similar. |

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500&family=JetBrains+Mono:wght@400;500&family=Sora:wght@600;700&display=swap" rel="stylesheet">
```

Type scale (ratio 1.25): 12, 15, 19, 24, 30, 37, 47, 59 px. Hero headline is
59 px Sora 700 (40 px on mobile), section titles are 37 px Sora 600, and body
text is 17–19 px Inter. Headings use line-height 1.1–1.2.

## Logo files and usage

| File | Use |
|---|---|
| `logo-lockup.svg` | Horizontal logo for light backgrounds (graphite wordmark, violet-ended ring, clear lens) |
| `logo-lockup-dark.svg` | Horizontal logo for dark backgrounds (fog wordmark, lavender-ended ring, glass lens) |
| `logo-mark.svg` / `logo-mark-dark.svg` | Comet mark only, tight crop, transparent |
| `wordmark.svg` / `wordmark-dark.svg` | Wordmark only (outlined Sora 600) |
| `app-icon.svg` | macOS app icon source (1024 grid, 824 body, continuous corners) |
| `favicon.svg` | Favicon: graphite rounded tile with the hinted comet. Works on light and dark tabs |
| `png/app-icon-{1024,512,256,128}.png` | App icon renders (hero, README) |
| `png/mark-{512,192}.png`, `png/mark-dark-{512,192}.png` | Mark on a transparent square (web manifest, avatars) |
| `png/apple-touch-icon-180.png` | Opaque, full-bleed graphite with glow (iOS applies its own mask) |
| `png/favicon-{32,16}.png` | Raster favicon fallbacks |
| `png/logo-lockup.png`, `png/logo-lockup-dark.png` | 160 px tall raster lockups |

```html
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="icon" href="png/favicon-32.png" sizes="32x32" type="image/png">
<link rel="apple-touch-icon" href="png/apple-touch-icon-180.png">
```

- **Clear space:** keep at least the lens's outer diameter × 0.5 free on every
  side of the mark or lockup.
- **Minimum size:** the lockup at 20 px tall. Below 24 px use the mark alone,
  and below 20 px use `favicon.svg` (the hinted variant).
- **Backgrounds:** use the light lockup on paper, white or light grey, and the
  dark lockup on graphite, black or dark photos. On a busy or mid-tone
  background, use the app icon instead.
- **Don't:**
  - add a handle to the lens
  - flip or re-angle the motion (it always launches up and to the right at 30°)
  - drop the spark from the full-size mark
  - recolour the ring outside the orange → pink → violet range
  - set the name in another font or in all caps
  - write it as "FastLight" or "Fast Light". The name is **Fastlight**.
- Never use the word "Spotlight" in the logo or product name. Describe it as
  "a Spotlight-style launcher" in prose only.

## App icon notes

- The canvas is 1024 with an 824×824 body inset 100 px and a continuous-corner squircle.
- The tile is a graphite gradient (`#34353F` → `#15161B`) with a radial
  pink → violet glow centred on the lens. On top sit 5% film grain (against
  banding), a soft drop shadow and a faint top rim light.
- The lens is opaque cool glass (`#5D67A8` → `#3A406E`) with a pale sheen, a
  thin lavender inner glow and a crisp white specular arc. The ring and
  trails carry a soft bloom.
- The 16 and 32 px slots in the `.icns` use `src/app-icon-small.svg`, which is
  flat with the hinted comet.
- Menu bar: `Resources/MenuBarIcon.png` (18 px, two tails + ring + spark) and
  `@2x` (36 px, three tails + ring + spark). Both are pure black on
  transparent, to be loaded as a template image (`isTemplate = true`).

## Regenerating

```sh
scripts/render-brand.sh          # SVG -> all PNGs, AppIcon.icns, menu bar icons (needs: brew install resvg)
scripts/render-brand.sh --svg    # also regenerate SVG sources from src/generate.py (needs uv + network for Sora)
```

Earlier explorations (navy original, Daylight, Sunrise, background studies)
are kept in `variants/`, together with their contact-sheet scripts.
