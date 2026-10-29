#!/usr/bin/env python3
"""Generates assets/fx/crack1.png and crack2.png: transparent egg-shell crack
overlays (dark zig-zag lines) used as the egg's material_overlay.
    python3 tools/gen_fx.py
"""
import math
import os
import random

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fx")


def crack(seed: int, branches: int, out: str) -> None:
    random.seed(seed)
    size = 256
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ink = (40, 22, 10, 255)
    for _ in range(branches):
        x, y = random.uniform(60, 196), random.uniform(30, 90)
        a = random.uniform(math.pi * 0.3, math.pi * 0.7)
        w = 7.0
        for _ in range(random.randint(6, 10)):
            a += random.uniform(-0.9, 0.9)
            nx = x + math.cos(a) * random.uniform(14, 26)
            ny = y + math.sin(a) * random.uniform(14, 26)
            d.line([(x, y), (nx, ny)], fill=ink, width=max(2, int(w)))
            if random.random() < 0.35:
                ba = a + random.choice([-1, 1]) * random.uniform(0.6, 1.2)
                d.line([(nx, ny), (nx + math.cos(ba) * 18, ny + math.sin(ba) * 18)], fill=ink, width=max(2, int(w * 0.6)))
            x, y = nx, ny
            w *= 0.85
    im.save(out)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    crack(3, 2, os.path.join(OUT, "crack1.png"))
    crack(11, 5, os.path.join(OUT, "crack2.png"))
