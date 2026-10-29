#!/usr/bin/env python3
"""Generates the UI icons in assets/ui/ (64x64 SVG, white fill, ink outline).

Every icon is drawn twice: a thick ink pass underneath, then the fill on top,
which gives the same chunky outline as the toon materials. Re-run after edits:
    python3 tools/gen_icons.py
"""
import math
import os

INK = "#1a1420"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")
O = 5  # outline width (each side)


def svg(body: str, size: int = 64) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 {size} {size}">{body}</svg>\n')


def shape(d: str, fill: str = "#fff") -> str:
    """Filled path with outer ink outline."""
    return (f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="{O * 2}" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="{fill}"/>')


def line(d: str, w: float = 9, color: str = "#fff") -> str:
    """Stroked path (round caps) with ink outline."""
    halo = w + O * 2 if color != INK else w
    return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{halo}" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>')


def poly(points) -> str:
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in points) + " Z"


def circle_d(cx, cy, r) -> str:
    return f"M{cx - r} {cy} a{r} {r} 0 1 0 {r * 2} 0 a{r} {r} 0 1 0 {-r * 2} 0 Z"


def rrect_d(x, y, w, h, r) -> str:
    return (f"M{x + r} {y} H{x + w - r} Q{x + w} {y} {x + w} {y + r} V{y + h - r} Q{x + w} {y + h} {x + w - r} {y + h} "
            f"H{x + r} Q{x} {y + h} {x} {y + h - r} V{y + r} Q{x} {y} {x + r} {y} Z")


def star_points(cx, cy, r_out, r_in, n, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + i * math.pi / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def gear() -> str:
    pts = []
    teeth = 8
    for i in range(teeth * 4):
        a = i * math.pi * 2 / (teeth * 4)
        r = 27 if (i % 4) in (0, 1) else 20
        pts.append((32 + math.cos(a) * r, 32 + math.sin(a) * r))
    return shape(poly(pts)) + f'<circle cx="32" cy="32" r="8" fill="{INK}"/>'


ICONS = {
    "play": shape("M21 11 Q19 10 19 13 V51 Q19 54 21 53 L52 34 Q54 32 52 30 Z"),
    "left": line("M38 13 L20 32 L38 51", 11),
    "right": line("M26 13 L44 32 L26 51", 11),
    "pause": shape(rrect_d(15, 12, 12, 40, 4)) + shape(rrect_d(37, 12, 12, 40, 4)),
    "close": line("M18 18 L46 46 M46 18 L18 46", 11),
    "gear": gear(),
    "refresh": line("M47 40 A17 17 0 1 1 40 18", 9) + shape(poly([(34, 8), (51, 17), (36, 29)])),
    "download": line("M32 9 V28", 10) + shape(poly([(18, 30), (46, 30), (32, 45)])) + line("M12 47 V54 H52 V47", 8),
    "home": shape("M32 9 L56 31 H49 V54 H15 V31 H8 Z") + f'<path d="{rrect_d(27, 38, 10, 16, 2)}" fill="{INK}"/>',
    "bang": shape(poly(star_points(32, 32, 26, 14, 9)), "#ff5a5f") + shape(poly(star_points(32, 32, 12, 7, 9, 0.3)), "#ffd23f"),
    "timer": shape(rrect_d(26, 4, 12, 9, 3)) + shape(circle_d(32, 37, 20)) + line("M32 37 V26 M32 37 L40 41", 3, INK),
    "jump": shape("M32 7 L55 32 H42 V55 H22 V32 H9 Z"),
    "grab": "".join(shape(rrect_d(x, y, 10, 24, 5)) for x, y in [(12, 14), (23, 8), (34, 9), (45, 15)])
    + shape(rrect_d(11, 26, 44, 30, 13)) + shape(rrect_d(4, 32, 14, 10, 5)),
    # fist with speed lines (PUSH / THROW / SHOOT button)
    "act": line("M4 22 H13 M2 33 H11 M4 44 H13", 5)
    + shape(rrect_d(18, 14, 40, 36, 12))
    + line("M29 16 V30 M39 16 V30 M49 18 V30", 3, INK)
    + shape(rrect_d(16, 34, 22, 14, 6)),
    "crown": shape("M8 50 L12 18 L24 32 L32 12 L40 32 L52 18 L56 50 Z", "#ffd23f")
    + f'<circle cx="32" cy="40" r="4" fill="{INK}"/>',
}


def burst() -> str:
    """Soft sunburst behind the logo (white rays, transparent between)."""
    rays = 18
    body = ""
    for i in range(rays):
        a0 = i * 2 * math.pi / rays
        a1 = a0 + math.pi / rays
        body += f'<path d="M256 256 L{256 + math.cos(a0) * 256:.1f} {256 + math.sin(a0) * 256:.1f} L{256 + math.cos(a1) * 256:.1f} {256 + math.sin(a1) * 256:.1f} Z"/>'
    return svg('<defs><radialGradient id="g"><stop offset="0.15" stop-color="#fff" stop-opacity="0.9"/>'
               '<stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>'
               f'<g fill="url(#g)">{body}</g>', 512)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, body in ICONS.items():
        with open(os.path.join(OUT, f"{name}.svg"), "w") as f:
            f.write(svg(body))
    with open(os.path.join(OUT, "burst.svg"), "w") as f:
        f.write(burst())


if __name__ == "__main__":
    main()
