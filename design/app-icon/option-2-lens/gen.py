import math, os, sys

OUT = sys.argv[1]
C = 512.0

def squircle(cx=512, cy=512, half=412, n=5.0, steps=360):
    pts = []
    for k in range(steps):
        t = 2 * math.pi * k / steps
        ct, st = math.cos(t), math.sin(t)
        x = half * math.copysign(abs(ct) ** (2 / n), ct)
        y = half * math.copysign(abs(st) ** (2 / n), st)
        pts.append((cx + x, cy + y))
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z"

SQ = squircle()
SQ_SMALL = squircle(half=416)

R_LENS = 322
R_BLADE = 258
R_HEX = 172
R_PUPIL = 120
GAP = 18
ROT = -90 + 15  # rotate the aperture so it isn't axis-aligned

def pol(r, deg):
    a = math.radians(deg)
    return (C + r * math.cos(a), C + r * math.sin(a))

def line_circle(p, q, r):
    # point beyond q along p->q that hits circle radius r
    dx, dy = q[0] - p[0], q[1] - p[1]
    fx, fy = q[0] - C, q[1] - C
    a = dx * dx + dy * dy
    b = 2 * (fx * dx + fy * dy)
    c = fx * fx + fy * fy - r * r
    t = (-b + math.sqrt(b * b - 4 * a * c)) / (2 * a)
    return (q[0] + t * dx, q[1] + t * dy)

N = 6
V = [pol(R_HEX, ROT + 360 * i / N) for i in range(N)]
P = [line_circle(V[i], V[(i + 1) % N], R_BLADE + 30) for i in range(N)]

def blade(i):
    a, b = V[(i + 1) % N], V[(i + 2) % N]
    p0, p1 = P[i], P[(i + 1) % N]
    return (f"M{a[0]:.2f},{a[1]:.2f} L{p0[0]:.2f},{p0[1]:.2f} "
            f"A{R_BLADE+30},{R_BLADE+30} 0 0 1 {p1[0]:.2f},{p1[1]:.2f} "
            f"L{b[0]:.2f},{b[1]:.2f} Z")

THEMES = {
    "default": dict(body="#f6f7fb", ring="#1a1a1a", bladeA="#3a3f48", bladeB="#454b55",
                    gap="#1a1a1a", pupil="#2563eb", shadow=0.30, bodyOp=1, extra=""),
    "dark": dict(body="#161a22", ring="#e5e7eb", bladeA="#384151", bladeB="#414b5c",
                 gap="#0f1115", pupil="#60a5fa", shadow=0.45, bodyOp=1, extra=""),
    "tinted": dict(body="#1c1d20", ring="#d9d9d9", bladeA="#5a5a5a", bladeB="#666666",
                   gap="#141414", pupil="#ffffff", shadow=0.45, bodyOp=1, extra=""),
    "clear": dict(body="url(#frost)", ring="#ffffff", bladeA="#ffffff", bladeB="#ffffff",
                  gap="none", pupil="#ffffff", shadow=0.22, bodyOp=1, extra="clear"),
}

def svg(name, t):
    clear = t["extra"] == "clear"
    defs = f"""
  <defs>
    <clipPath id="body-clip"><path d="{SQ}"/></clipPath>
    <clipPath id="blade-clip"><circle cx="512" cy="512" r="{R_BLADE}"/></clipPath>
    <filter id="icon-shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="14"/>
    </filter>"""
    if clear:
        defs += """
    <linearGradient id="frost" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.34"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0.18"/>
    </linearGradient>"""
    defs += "\n  </defs>"

    if clear:
        ring_op, blade_op_a, blade_op_b, pupil_op = 0.95, 0.38, 0.50, 1.0
    else:
        ring_op = blade_op_a = blade_op_b = pupil_op = 1.0

    blades = []
    for i in range(N):
        fill = t["bladeA"] if i % 2 == 0 else t["bladeB"]
        op = blade_op_a if i % 2 == 0 else blade_op_b
        stroke = "" if t["gap"] == "none" else f' stroke="{t["gap"]}" stroke-width="{GAP}" stroke-linejoin="round"'
        blades.append(f'      <path d="{blade(i)}" fill="{fill}" fill-opacity="{op}"{stroke}/>')
    blades = "\n".join(blades)

    # Clear: carve the aperture so the frosted body shows through; ring is a band (annulus).
    if clear:
        ring = (f'<path d="M{C-R_LENS},{C} a{R_LENS},{R_LENS} 0 1 0 {2*R_LENS},0 a{R_LENS},{R_LENS} 0 1 0 {-2*R_LENS},0 Z '
                f'M{C-R_BLADE},{C} a{R_BLADE},{R_BLADE} 0 1 1 {2*R_BLADE},0 a{R_BLADE},{R_BLADE} 0 1 1 {-2*R_BLADE},0 Z" '
                f'fill="{t["ring"]}" fill-opacity="{ring_op}"/>')
    else:
        ring = f'<circle cx="512" cy="512" r="{R_LENS}" fill="{t["ring"]}"/>'

    hexpath = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in V) + " Z"
    opening_fill = "none" if clear else t["body"]
    opening = "" if clear else f'\n      <path d="{hexpath}" fill="{opening_fill}" stroke="{opening_fill}" stroke-width="{GAP}" stroke-linejoin="round"/>'

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>picsee — Lens ({name})</title>{defs}
  <g id="shadow" opacity="{t['shadow']}">
    <path d="{SQ}" transform="translate(0 12)" fill="#000000" filter="url(#icon-shadow)"/>
  </g>
  <g id="layer-background">
    <path d="{SQ}" fill="{t['body']}"/>
  </g>
  <g clip-path="url(#body-clip)">
    <g id="layer-fg-1" data-role="lens ring">
      {ring}
    </g>
    <g id="layer-fg-2" data-role="aperture blades" clip-path="url(#blade-clip)">
{blades}{opening}
    </g>
    <g id="layer-fg-3" data-role="pupil (the one accent)">
      <circle cx="512" cy="512" r="{R_PUPIL}" fill="{t['pupil']}" fill-opacity="{pupil_op}"/>
    </g>
  </g>
</svg>
"""

def svg_small(name, t):
    """Optically corrected 16/32 px source with pixel-aligned circular edges."""
    clear = t["extra"] == "clear"
    body = "url(#frost)" if clear else t["body"]
    ring_op = 0.95 if clear else 1.0
    pupil_op = 1.0
    inner = "#ffffff" if clear else t["bladeA"]
    inner_op = 0.28 if clear else 1.0
    defs = f"""
  <defs>
    <clipPath id="body-clip"><path d="{SQ_SMALL}"/></clipPath>
    <filter id="icon-shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="14"/>
    </filter>"""
    if clear:
        defs += """
    <linearGradient id="frost" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.34"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0.18"/>
    </linearGradient>"""
    defs += "\n  </defs>"

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>picsee — Lens small ({name})</title>{defs}
  <g id="shadow" opacity="{t['shadow']}">
    <path d="{SQ_SMALL}" transform="translate(0 12)" fill="#000000" filter="url(#icon-shadow)"/>
  </g>
  <g id="layer-background">
    <path d="{SQ_SMALL}" fill="{body}"/>
  </g>
  <g clip-path="url(#body-clip)">
    <g id="layer-fg-1" data-role="lens ring">
      <circle cx="512" cy="512" r="320" fill="{t['ring']}" fill-opacity="{ring_op}"/>
      <circle cx="512" cy="512" r="256" fill="{inner}" fill-opacity="{inner_op}"/>
    </g>
    <g id="layer-fg-2" data-role="simplified aperture"/>
    <g id="layer-fg-3" data-role="pupil (the one accent)">
      <circle cx="512" cy="512" r="128" fill="{t['pupil']}" fill-opacity="{pupil_op}"/>
    </g>
  </g>
</svg>
"""

for name, t in THEMES.items():
    with open(os.path.join(OUT, f"icon-{name}.svg"), "w") as f:
        f.write(svg(name, t))
for name in ("default", "dark"):
    with open(os.path.join(OUT, f"icon-small{'-dark' if name == 'dark' else ''}.svg"), "w") as f:
        f.write(svg_small(name, THEMES[name]))
print("ok")
