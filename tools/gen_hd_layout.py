"""Generate high-res SVG art for the ocean boundary tiles and the UFO Workshop
(game units, SCALE x pixels). Run from the project root:
    python3 tools/gen_hd_layout.py"""
import random

SCALE = 8

def svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * SCALE}" height="{h * SCALE}" '
            f'viewBox="0 0 {w} {h}">\n{body}\n</svg>\n')

def pts(p):
    return " ".join(f"{x:.2f},{y:.2f}" for x, y in p)

# --- Boundary tiles: plum cobblestones in dark mortar --------------------------

MORTAR = "#222034"
STONE = "#45283c"
STONE_LIGHT = "#62405a"
STONE_DARK = "#33202f"
STONE_LINE = "#17142a"
GAP = 0.55

def split(rng, x, y, w, h, min_area, out):
    if w * h <= min_area or (w < 3.2 and h < 3.2):
        out.append((x, y, w, h))
        return
    if w >= h:
        c = w * rng.uniform(0.38, 0.62)
        split(rng, x, y, c, h, min_area, out)
        split(rng, x + c, y, w - c, h, min_area, out)
    else:
        c = h * rng.uniform(0.38, 0.62)
        split(rng, x, y, w, c, min_area, out)
        split(rng, x, y + c, w, h - c, min_area, out)

def stone(rng, x, y, w, h):
    """A rounded, slightly lumpy stone filling cell (x, y, w, h) minus the mortar gap."""
    g = GAP / 2
    x0, y0, x1, y1 = x + g, y + g, x + w - g, y + h - g
    c = min(1.3, (x1 - x0) / 2.8, (y1 - y0) / 2.8)
    j = lambda: rng.uniform(-0.22, 0.22)
    p = [(x0 + c + j(), y0 + j()), (x1 - c + j(), y0 + j()), (x1 + j(), y0 + c + j()), (x1 + j(), y1 - c + j()),
         (x1 - c + j(), y1 + j()), (x0 + c + j(), y1 + j()), (x0 + j(), y1 - c + j()), (x0 + j(), y0 + c + j())]
    # Smooth closed path through the corner-cut points (midpoint quadratic curves).
    n = len(p)
    mids = [((p[i][0] + p[(i + 1) % n][0]) / 2, (p[i][1] + p[(i + 1) % n][1]) / 2) for i in range(n)]
    d = f"M{mids[-1][0]:.2f},{mids[-1][1]:.2f} " + " ".join(
        f"Q{p[i][0]:.2f},{p[i][1]:.2f} {mids[i][0]:.2f},{mids[i][1]:.2f}" for i in range(n)) + " Z"
    hl = f"M{x0 + c:.2f},{y0 + 0.55:.2f} L{x1 - c:.2f},{y0 + 0.55:.2f}"
    sh = f"M{x0 + c:.2f},{y1 - 0.5:.2f} L{x1 - c:.2f},{y1 - 0.5:.2f}"
    return (f'<path d="{d}" fill="{STONE}" stroke="{STONE_LINE}" stroke-width="0.3"/>'
            f'<path d="{sh}" stroke="{STONE_DARK}" stroke-width="0.7" stroke-linecap="round"/>'
            f'<path d="{hl}" stroke="{STONE_LIGHT}" stroke-width="0.55" stroke-linecap="round"/>')

def cobble_sheet(name, tile_w, tile_h, shapes, min_area, seed):
    parts = []
    for i, shape in enumerate(shapes):
        rng = random.Random(seed + i * 101)
        ox = i * tile_w
        poly = [(ox + x, y) for x, y in shape]
        cells = []
        split(rng, ox, 0, tile_w, tile_h, min_area, cells)
        stones = "".join(stone(rng, *c) for c in cells)
        if len(shape) == 4:
            # Full tile: no clip, so neighbouring tiles meet without an antialiased seam.
            parts.append(f'<rect x="{ox}" y="0" width="{tile_w}" height="{tile_h}" fill="{MORTAR}"/>{stones}')
        else:
            parts.append(f'<clipPath id="t{i}"><polygon points="{pts(poly)}"/></clipPath>')
            parts.append(f'<g clip-path="url(#t{i})"><polygon points="{pts(poly)}" fill="{MORTAR}"/>{stones}</g>')
    with open(name, "w") as f:
        f.write(svg(tile_w * len(shapes), tile_h, "\n".join(parts)))

FULL8 = [(0, 0), (8, 0), (8, 16), (0, 16)]
cobble_sheet("entities/environment/ocean_boundaries/hd/ocean_wall.svg", 8, 16, [FULL8] * 3, 22, 7)
FULL16 = [(0, 0), (16, 0), (16, 16), (0, 16)]
cobble_sheet("entities/environment/ocean_boundaries/hd/ocean_floor.svg", 16, 16, [
    FULL16, FULL16, FULL16,
    [(0, 0), (16, 16), (0, 16)],   # 3: lower-left
    [(16, 0), (16, 16), (0, 16)],  # 4: lower-right
    [(0, 0), (16, 0), (0, 16)],    # 5: upper-left
    [(0, 0), (16, 0), (16, 16)],   # 6: upper-right
], 44, 11)

# --- UFO Workshop: turtle-shell hut with a shimmering UFO sign ------------------

OUT = "#323c39"
SHELL = "#6abe30"
RIM = "#37946e"
PLATE = "#4b692f"
WOOD = "#8f563b"
GRAIN = "#70412e"
YELLOW = "#fbf236"
GREEN = "#99e550"
DOOR = "#222034"
STEP = "#76428a"
GROUND = "#663931"

DOME = "M2,22.8 L1.4,12 C1.4,5 6,0.6 12,0.6 C18,0.6 22.6,5 22.6,12 L22,22.8 Z"
PLATES = ["M1.6,16.5 L5.2,15.2 L7.8,16.2", "M16.2,16.2 L18.8,15.2 L22.4,16.5", "M5.2,15.2 L5.5,12.4",
          "M18.8,15.2 L18.5,12.4", "M5.2,15.2 L5,19.2 L7.8,20.4", "M18.8,15.2 L19,19.2 L16.2,20.4",
          "M5,19.2 L1.8,20.2", "M19,19.2 L22.2,20.2", "M6.2,3.6 L9.4,1.5", "M17.8,3.6 L14.6,1.5",
          "M9.4,1.5 L12,2.9 L14.6,1.5"]
LETTERS = {
    "U": "M4.3,5.8 V9.1 Q4.3,10.7 5.85,10.7 Q7.4,10.7 7.4,9.1 V5.8",
    "F": "M10.5,10.7 V5.8 H13.3 M10.5,8.1 H12.8",
}

def workshop(lit):
    """lit: which letter shimmers green this frame (or None)."""
    b = [f'<rect x="0" y="22.6" width="24" height="1.4" fill="{GROUND}"/>',
         f'<clipPath id="d"><path d="{DOME}"/></clipPath>',
         f'<path d="{DOME}" fill="{SHELL}"/>',
         f'<g clip-path="url(#d)"><path d="{DOME}" fill="none" stroke="{RIM}" stroke-width="1.9"/>'
         + "".join(f'<path d="{p}" fill="none" stroke="{PLATE}" stroke-width="0.5" stroke-linecap="round" stroke-linejoin="round"/>' for p in PLATES)
         + "</g>",
         f'<path d="{DOME}" fill="none" stroke="{OUT}" stroke-width="0.7" stroke-linejoin="round"/>',
         # door
         f'<path d="M8.2,22.6 V18 A3.8,3.8 0 0 1 15.8,18 V22.6 Z" fill="{DOOR}" stroke="{YELLOW}" stroke-width="0.75" stroke-linejoin="round"/>',
         f'<rect x="8.7" y="21.3" width="6.6" height="1.0" fill="{STEP}"/>',
         # sign
         f'<polygon points="0.2,5.3 22.9,3.4 23.6,10.5 0.8,12.5" fill="{WOOD}" stroke="#000" stroke-width="0.7" stroke-linejoin="round"/>',
         f'<path d="M1.6,11.2 L9,10.6 M14.5,4.6 L22,4" stroke="{GRAIN}" stroke-width="0.35" stroke-linecap="round"/>']
    letters = []
    for k, d in LETTERS.items():
        col = GREEN if lit == k else YELLOW
        letters.append(f'<path d="{d}" fill="none" stroke="#000" stroke-width="2.0" stroke-linecap="round" stroke-linejoin="round"/>'
                       f'<path d="{d}" fill="none" stroke="{col}" stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round"/>')
    col = GREEN if lit == "O" else YELLOW
    letters.append(f'<ellipse cx="17.4" cy="8.2" rx="1.85" ry="2.45" fill="none" stroke="#000" stroke-width="2.0"/>'
                   f'<ellipse cx="17.4" cy="8.2" rx="1.85" ry="2.45" fill="none" stroke="{col}" stroke-width="1.1"/>')
    b.append(f'<g transform="rotate(-4.6 12 8)">{"".join(letters)}</g>')
    return svg(24, 24, "\n".join(b))

for i, lit in enumerate([None, "U", "F", "O", None]):
    with open(f"entities/environment/ufo_workshop/sprites/hd/workshop_{i}.svg", "w") as f:
        f.write(workshop(lit))
print("ok")
