"""Generate high-res line-art SVG frames for the turtle (24x24 game units, 8x pixels).
One north-facing design per frame; the game turns it to any angle (free rotation),
and the shell highlight is a separate layer that never rotates.
Run from the project root:  python3 tools/gen_hd_turtle.py"""
import math

SCALE = 8
OUT = "entities/player/sprites/hd"
C = 12.0         # frame centre
R = 8.0          # shell radius
LINE = "#323c39"
RIM = "#37946e"
PLATE = "#4b692f"
SHELL = "#6abe30"
SHINE = "#a8e86e"
SKIN = "#37946e"
EYE = "#fbf236"
W = 0.7

def polar(deg, r):
    a = math.radians(deg)
    return C + r * math.sin(a), C - r * math.cos(a)

def paddle(deg, length, width):
    """A flipper pointing out from the shell at `deg` (0 = north, clockwise)."""
    hw = width / 2
    d = (f"M{-hw},0 C{-hw * 1.5},{-length * 0.55} {-hw * 0.8},{-length} 0,{-length} "
         f"C{hw * 0.8},{-length} {hw * 1.5},{-length * 0.55} {hw},0 Z")
    bx, by = polar(deg, R - 1.4)
    return (f'<path d="{d}" transform="translate({bx:.2f} {by:.2f}) rotate({deg} 0 0) translate(0 {-1.4 + 0.0})" '
            f'fill="{SKIN}" stroke="{LINE}" stroke-width="{W}" stroke-linejoin="round"/>')

def head():
    hx, hy = C, C - R - 0.9
    return (f'<ellipse cx="{hx}" cy="{hy + 0.6}" rx="1.5" ry="1.8" fill="{SKIN}" stroke="{LINE}" stroke-width="{W}"/>'
            f'<ellipse cx="{hx}" cy="{hy - 0.9}" rx="2.1" ry="2.0" fill="{SKIN}" stroke="{LINE}" stroke-width="{W}"/>'
            f'<circle cx="{hx - 0.95}" cy="{hy - 1.5}" r="0.6" fill="{EYE}" stroke="{LINE}" stroke-width="0.3"/>'
            f'<circle cx="{hx + 0.95}" cy="{hy - 1.5}" r="0.6" fill="{EYE}" stroke="{LINE}" stroke-width="0.3"/>')

def shell():
    hexr = 2.9
    hexpts = [polar(a, hexr) for a in range(0, 360, 60)]
    ring = 6.1
    parts = [f'<clipPath id="s"><circle cx="{C}" cy="{C}" r="{R}"/></clipPath>',
             f'<circle cx="{C}" cy="{C}" r="{R}" fill="{SHELL}"/>',
             f'<g clip-path="url(#s)">',
             f'<circle cx="{C}" cy="{C}" r="{R}" fill="none" stroke="{RIM}" stroke-width="2.6"/>',
             f'<circle cx="{C}" cy="{C}" r="{ring}" fill="none" stroke="{PLATE}" stroke-width="0.5"/>',
             f'<polygon points="{" ".join(f"{x:.2f},{y:.2f}" for x, y in hexpts)}" fill="none" stroke="{PLATE}" stroke-width="0.55" stroke-linejoin="round"/>']
    for a in range(0, 360, 60):
        x0, y0 = polar(a, hexr)
        x1, y1 = polar(a, ring)
        parts.append(f'<line x1="{x0:.2f}" y1="{y0:.2f}" x2="{x1:.2f}" y2="{y1:.2f}" stroke="{PLATE}" stroke-width="0.55" stroke-linecap="round"/>')
    for a in range(30, 360, 60):  # marginal scute seams
        x0, y0 = polar(a, ring)
        x1, y1 = polar(a, R)
        parts.append(f'<line x1="{x0:.2f}" y1="{y0:.2f}" x2="{x1:.2f}" y2="{y1:.2f}" stroke="{PLATE}" stroke-width="0.45"/>')
    parts.append("</g>")
    parts.append(f'<circle cx="{C}" cy="{C}" r="{R - W / 2}" fill="none" stroke="{LINE}" stroke-width="{W}"/>')
    return "".join(parts)

# Limb poses: (front angle, front length, back angle, back length)
## Lengths stay <= 3.6 so a limb pointing at a frame edge isn't clipped (8 + 3.6 < 12).
KICK = [(58, 3.0, 148, 2.4), (88, 3.6, 168, 3.4)]

def frame(kind, i):
    body = []
    if kind == "kick":
        fa, fl, ba, bl = KICK[i]
        for s in (1, -1):
            body.append(paddle(s * fa, fl, 2.6))
            body.append(paddle(s * ba, bl, 2.0))
    if kind == "shoot":
        body.append(head())
    body.append(shell())
    return "".join(body)

def shine():
    """Highlight stays top-left whatever way the turtle faces (the light doesn't turn)."""
    sx0, sy0 = polar(-50, R - 2.2)
    sx1, sy1 = polar(-15, R - 2.2)
    return (f'<path d="M{sx0:.2f},{sy0:.2f} A{R - 2.2},{R - 2.2} 0 0 1 {sx1:.2f},{sy1:.2f}" '
            f'fill="none" stroke="{SHINE}" stroke-width="0.8" stroke-linecap="round"/>')

def svg(body):
    px = 24 * SCALE
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}" viewBox="0 0 24 24">{body}</svg>\n'

names = []
for kind, count in (("idle", 1), ("kick", 2), ("shoot", 1)):
    for i in range(count):
        name = f"turtle_{kind}_free_{i}"
        open(f"{OUT}/{name}.svg", "w").write(svg(frame(kind, i)))
        names.append(name)
open(f"{OUT}/turtle_shine.svg", "w").write(svg(shine()))
print(len(names), "frames + shine")
