"""Generate high-res line-art SVG frames for the piranha (16x16 game units, 8x pixels).
Usage: python3 tools/gen_hd_piranha.py entities/enemies/piranha/sprites/hd"""
import os, sys

OUT = sys.argv[1]
SCALE = 8
SIZE = 16
W = 0.55  # outline width in game units

SKINS = {
    "red":    dict(body="#c0343e", back="#8e2232", belly="#e2606a", fin="#e8873a", eye="#f8d838", line="#1c1730", mouth="#4a1f4a"),
    "pink":   dict(body="#de78b8", back="#b0508e", belly="#f2a6d4", fin="#e8873a", eye="#86d84e", line="#1c1730", mouth="#4a1f4a"),
    "yellow": dict(body="#f8e244", back="#e8b830", belly="#fff3a0", fin="#f0a040", eye="#f8f8f0", line="#8a3a1a", mouth="#e892c8"),
}

def mouth_open(top, bot):
    # (jaw tip top y, hinge, jaw tip bottom y) — a wedge cut into the snout
    return top, bot

def fish(skin, gape, x_mark=False, sparkles=()):
    s = SKINS[skin]
    ty, by = gape  # upper/lower lip y at the snout tip (x=15)
    hx, hy = 11.4, 8.7  # mouth hinge
    body = (f"M3.6,8.4 C3.6,4.8 6.6,2.8 10,2.9 C12.6,3 14.5,4.4 15.1,{ty} "
            f"L{hx},{hy} L15.1,{by} C14.4,13.2 12.2,14.6 9.6,14.6 C6.2,14.6 3.6,12 3.6,8.4 Z")
    p = []
    # tail, dorsal and lower fin sit behind the body
    p.append(f'<path d="M4.4,8.4 L0.7,4.4 Q1.4,8.4 0.7,12.4 Z" fill="{s["back"]}" stroke="{s["line"]}" stroke-width="{W}" stroke-linejoin="round"/>')
    p.append(f'<path d="M6.2,3.9 Q7.6,0.2 12.2,3.2 Z" fill="{s["fin"]}" stroke="{s["line"]}" stroke-width="{W}" stroke-linejoin="round"/>')
    p.append(f'<path d="M7.2,14.2 Q8.2,16 10.2,14.5 Z" fill="{s["fin"]}" stroke="{s["line"]}" stroke-width="{W}" stroke-linejoin="round"/>')
    # mouth interior behind the body notch
    p.append(f'<path d="M15.1,{ty} L{hx - 0.3},{hy} L15.1,{by} Q14.2,{(ty + by) / 2:.2f} 15.1,{ty} Z" fill="{s["mouth"]}" '
             f'stroke="{s["line"]}" stroke-width="{W * 0.5}" stroke-linejoin="round"/>')
    # body + shading (clipped)
    p.append(f'<defs><clipPath id="b"><path d="{body}"/></clipPath></defs>')
    p.append(f'<g clip-path="url(#b)"><path d="{body}" fill="{s["body"]}"/>'
             f'<path d="M2,6.6 C5,3.4 9,2.4 16,3.6 L16,0 L2,0 Z" fill="{s["back"]}"/>'
             f'<path d="M3,11.4 C6,12.6 10,12.8 16,11 L16,16 L3,16 Z" fill="{s["belly"]}"/></g>')
    # two white teeth per jaw, bases on the lip so the body outline covers them
    def lip(y_tip, x):
        return hy + (y_tip - hy) * (x - hx) / (15.1 - hx)
    for f in (0.42, 0.8):
        x = hx + (15.1 - hx) * f
        for y_tip, d in ((ty, 1), (by, -1)):
            a, b = x - 0.5, x + 0.5
            p.append(f'<path d="M{a:.2f},{lip(y_tip, a):.2f} L{b:.2f},{lip(y_tip, b):.2f} L{x:.2f},{lip(y_tip, x) + d * 1.15:.2f} Z" fill="#fff"/>')
    p.append(f'<path d="{body}" fill="none" stroke="{s["line"]}" stroke-width="{W}" stroke-linejoin="round"/>')
    # gill + pectoral fin
    p.append(f'<path d="M8.4,6.4 Q7.4,8.8 8.6,11" fill="none" stroke="{s["line"]}" stroke-width="{W * 0.6}" stroke-linecap="round"/>')
    p.append(f'<path d="M7.6,9.4 Q5.6,9.2 5.2,11 Q6.8,11.4 7.6,9.4 Z" fill="{s["fin"]}" stroke="{s["line"]}" stroke-width="{W * 0.6}" stroke-linejoin="round"/>')
    # eye + angry brow
    p.append(f'<circle cx="11.3" cy="5.7" r="1.55" fill="{s["eye"]}" stroke="{s["line"]}" stroke-width="{W * 0.8}"/>')
    p.append(f'<circle cx="11.75" cy="5.85" r="0.7" fill="{s["line"]}"/><circle cx="12.0" cy="5.55" r="0.22" fill="#fff"/>')
    p.append(f'<path d="M9.4,3.9 L13.2,4.9" stroke="{s["line"]}" stroke-width="{W * 1.1}" stroke-linecap="round"/>')
    if x_mark:
        p.append(f'<path d="M5.6,6.0 L7.0,7.4 M7.0,6.0 L5.6,7.4" stroke="{s["line"]}" stroke-width="{W * 0.8}" stroke-linecap="round"/>')
    for (x, y, r) in sparkles:
        p.append(f'<path d="M{x},{y - r} Q{x},{y} {x + r},{y} Q{x},{y} {x},{y + r} Q{x},{y} {x - r},{y} Q{x},{y} {x},{y - r} Z" '
                 f'fill="#d8f86a" stroke="#6a9a2a" stroke-width="{W * 0.35}"/>')
    px = SIZE * SCALE
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}" viewBox="0 0 {SIZE} {SIZE}">\n'
            + "\n".join(p) + "\n</svg>\n")

WIDE, NARROW = (6.2, 11.6), (7.2, 10.4)
frames = {
    "piranha_swim_0": fish("red", WIDE),
    "piranha_swim_1": fish("red", NARROW),
    "piranha_hurt_0": fish("pink", WIDE, x_mark=True),
    "piranha_hurt_1": fish("pink", NARROW, x_mark=True),
    "piranha_flash_0": fish("yellow", WIDE, sparkles=[(1.4, 1.6, 1.2), (14.4, 1.4, 0.9), (2.2, 14.6, 0.9)]),
    "piranha_flash_1": fish("yellow", NARROW, sparkles=[(3.0, 1.2, 0.9), (13.6, 14.6, 1.2), (0.9, 13.4, 1.1)]),
    "piranha_flash_2": fish("yellow", WIDE, sparkles=[(1.0, 2.6, 0.9), (13.0, 1.0, 1.1), (14.8, 14.0, 0.9)]),
}
for name, text in frames.items():
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(text)
print("\n".join(frames))
