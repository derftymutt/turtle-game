"""Generate high-res line-art SVGs for CircularBumper.
Each SVG's viewBox is in game units (same frame size as the pixel sprite);
width/height = viewBox * SCALE so Godot imports at SCALE x resolution."""
import math, os, sys

OUT = sys.argv[1]
SCALE = 8
STROKE = 0.7

# Colourways sampled from the pixel sprites.
PLANETS = {
    "a": dict(base="#5b6ce2", shade="#2f5d7c", light="#8a9cf5", s1="#e0955c", s2="#d474b6", line="#15131f"),
    "b": dict(base="#6db3f8", shade="#3f7fc9", light="#b4dcff", s1="#f8ef45", s2="#e57fc0", line="#7a4d2a"),
    "c": dict(base="#5acbe2", shade="#2f8fb0", light="#a8eef7", s1="#93e264", s2="#e2545a", line="#5a2f80"),
}
RING = "#e0627a"
GIANTS = {
    "1": dict(top="#7d4c9c", band1="#db4d5e", band2="#a53346", grey="#8c8c94", bottom="#4b4b8e", spot="#f07a6a", line="#15131f"),
    "2": dict(top="#97e05a", band1="#e47bc6", band2="#e0782e", grey="#8c8c94", bottom="#7d4c9c", spot="#f2a0dc", line="#8a3f7a"),
    "3": dict(top="#66bb3a", band1="#f8ea3c", band2="#e0782e", grey="#8c8c94", bottom="#b8322e", spot="#ffd25a", line="#8a3a12"),
}

def wave(x0, x1, y, amp, freq, phase, slope, n=24):
    pts = []
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        pts.append((x, y + slope * (x - x0) + amp * math.sin(freq * x + phase)))
    return pts

def band_path(x0, x1, y, h, amp, freq, phase, slope):
    top = wave(x0, x1, y, amp, freq, phase, slope)
    bot = wave(x0, x1, y + h, amp * 0.8, freq, phase + 0.6, slope)[::-1]
    pts = top + bot
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z"

def svg(size, body):
    px = size * SCALE
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}" '
            f'viewBox="0 0 {size} {size}">\n{body}\n</svg>\n')

def planet(cx, cy, r, p, uid):
    """Banded little planet: flat fill, diagonal wavy stripes, shade crescent, highlight, bold outline."""
    clip = f'<clipPath id="c{uid}"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath>'
    stripes = []
    x0, x1 = cx - r - 1, cx + r + 1
    for i, (dy, col, h) in enumerate([(-8.2, "s1", 1.5), (-4.4, "s2", 1.1), (-1.2, "s1", 1.6),
                                      (2.6, "s2", 1.2), (5.8, "s1", 1.5), (8.8, "s2", 1.0)]):
        stripes.append(f'<path d="{band_path(x0, x1, cy + dy * r / 12, h * r / 12, 0.55 * r / 12, 0.9 * 12 / r, i * 1.7, -0.32)}" '
                       f'fill="{p[col]}" stroke="{p["line"]}" stroke-width="{STROKE * 0.45}" stroke-linejoin="round"/>')
    shade = (f'<path d="M{cx - r * 0.55:.2f},{cy - r * 0.84:.2f} A{r},{r} 0 0 0 {cx - r * 0.55:.2f},{cy + r * 0.84:.2f} '
             f'A{r * 1.1:.2f},{r * 1.1:.2f} 0 0 1 {cx - r * 0.55:.2f},{cy - r * 0.84:.2f} Z" fill="{p["shade"]}" opacity="0.85"/>')
    shade = (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{p["shade"]}" opacity="0.8" '
             f'mask="url(#m{uid})"/>')
    mask = (f'<mask id="m{uid}"><rect x="0" y="0" width="200" height="200" fill="white"/>'
            f'<circle cx="{cx + r * 0.28:.2f}" cy="{cy - r * 0.1:.2f}" r="{r * 0.98:.2f}" fill="black"/></mask>')
    hl = (f'<path d="M{cx + r * 0.25:.2f},{cy - r * 0.72:.2f} A{r * 0.75:.2f},{r * 0.75:.2f} 0 0 1 {cx + r * 0.72:.2f},{cy - r * 0.2:.2f}" '
          f'fill="none" stroke="{p["light"]}" stroke-width="{STROKE * 1.1}" stroke-linecap="round"/>')
    return (f'<defs>{clip}{mask}</defs>'
            f'<g clip-path="url(#c{uid})"><circle cx="{cx}" cy="{cy}" r="{r}" fill="{p["base"]}"/>'
            + "".join(stripes) + shade + hl + '</g>'
            f'<circle cx="{cx}" cy="{cy}" r="{r - STROKE / 2:.2f}" fill="none" stroke="{p["line"]}" stroke-width="{STROKE}"/>')

def ring_half(cx, cy, rx, ry, angle, front, line):
    """Half of a tilted ellipse ring drawn as a thick band with outlines."""
    sweep = 1 if front else 0
    def pt(t):
        x, y = rx * math.cos(t), ry * math.sin(t)
        a = math.radians(angle)
        return cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)
    (ax, ay), (bx, by) = pt(0), pt(math.pi)
    d = f"M{ax:.2f},{ay:.2f} A{rx},{ry} {angle} 0 {sweep} {bx:.2f},{by:.2f}"
    return (f'<path d="{d}" fill="none" stroke="{line}" stroke-width="{STROKE * 3.2}" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="{RING}" stroke-width="{STROKE * 1.8}" stroke-linecap="round"/>')

def ringed(p, mirror, uid):
    size, c, r = 36, 18, 12
    angle = 24
    line = p["line"]
    body = (ring_half(c, c, 16.6, 5.0, angle, False, line) + planet(c, c, r, p, uid)
            + ring_half(c, c, 16.6, 5.0, angle, True, line))
    if mirror:
        body = f'<g transform="translate({size},0) scale(-1,1)">{body}</g>'
    return svg(size, body)

def giant(g, uid):
    size, c, r = 32, 16, 16
    clip = f'<clipPath id="c{uid}"><circle cx="{c}" cy="{c}" r="{r}"/></clipPath>'
    bands = [(-16, g["top"], 32), (-9.5, g["band1"], 2.4), (-6.2, g["band2"], 1.6), (-3.2, g["grey"], 3.4),
             (0.6, g["band1"], 3.6), (4.6, g["band2"], 1.8), (7.0, g["band1"], 2.0), (9.4, g["bottom"], 12)]
    parts = []
    for i, (dy, col, h) in enumerate(bands):
        parts.append(f'<path d="{band_path(-1, 33, c + dy, h, 0.45, 0.75, i * 1.3, 0.0)}" fill="{col}" '
                     f'stroke="{g["line"]}" stroke-width="{STROKE * 0.4}" stroke-linejoin="round"/>')
    spot = (f'<ellipse cx="{c - 4}" cy="{c + 2.4}" rx="3.2" ry="1.5" fill="{g["spot"]}" '
            f'stroke="{g["line"]}" stroke-width="{STROKE * 0.5}"/>')
    shade = (f'<circle cx="{c}" cy="{c}" r="{r}" fill="#000" opacity="0.22" mask="url(#m{uid})"/>')
    mask = (f'<mask id="m{uid}"><rect width="200" height="200" fill="white"/>'
            f'<circle cx="{c - 2.5}" cy="{c - 2.5}" r="{r * 0.98:.2f}" fill="black"/></mask>')
    hl = (f'<path d="M{c - 9:.2f},{c - 10:.2f} A12,12 0 0 1 {c + 1:.2f},{c - 13.2:.2f}" fill="none" '
          f'stroke="#fff" stroke-opacity="0.55" stroke-width="{STROKE * 1.1}" stroke-linecap="round"/>')
    body = (f'<defs>{clip}{mask}</defs><g clip-path="url(#c{uid})">' + "".join(parts) + spot + shade + hl + '</g>'
            f'<circle cx="{c}" cy="{c}" r="{r - STROKE / 2:.2f}" fill="none" stroke="{g["line"]}" stroke-width="{STROKE}"/>')
    return svg(size, body)

files = {}
for k, p in PLANETS.items():
    files[f"planet_{k}.svg"] = svg(24, planet(12, 12, 12, p, k))
    files[f"ringed_{k}.svg"] = ringed(p, False, "r" + k)
    files[f"ringed_{k}_flip.svg"] = ringed(p, True, "f" + k)
# The medium bumper (giant_*) now uses hand-drawn art: sprites/hd/bumper_medium_*.png.
# Uncomment to regenerate the old line-art versions.
# for k, g in GIANTS.items():
#     files[f"giant_{k}.svg"] = giant(g, "g" + k)
for name, text in files.items():
    with open(os.path.join(OUT, name), "w") as f:
        f.write(text)
print("\n".join(sorted(files)))
