#!/usr/bin/env python3
"""Generates the procedural textures used by the world dressing (sky, clouds, vegetation, runways).

Run from this directory:  python3 make_world_textures.py
Outputs (all original, generated here, no external assets):
  tree_atlas.png     1024x256, four species side by side: pine, olive, palm, shrub (RGBA, alpha = foliage)
  runway_digits.png  1280x256, digits 0..9 side by side, white on transparent (runway designators)
  cloud_noise.png    256x256 tileable greyscale fBm (cloud shapes, R channel)
  asphalt.png        256x256 tileable greyscale (runway and taxiway surface, R channel)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RNG = np.random.default_rng(20261009)


def periodic_noise(size: int, cells: int, rng) -> np.ndarray:
    """Tileable value noise: random lattice of `cells` x `cells`, smooth bilinear interpolation."""
    lattice = rng.random((cells, cells))
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int)
    f = coords - i0
    f = f * f * (3.0 - 2.0 * f)
    i1 = (i0 + 1) % cells
    i0 = i0 % cells
    rows0 = lattice[i0]
    rows1 = lattice[i1]
    a = rows0[:, i0] * (1 - f)[None, :] + rows0[:, i1] * f[None, :]
    b = rows1[:, i0] * (1 - f)[None, :] + rows1[:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(size: int, base_cells: int, octaves: int, rng) -> np.ndarray:
    total = np.zeros((size, size))
    amp = 1.0
    norm = 0.0
    cells = base_cells
    for _ in range(octaves):
        total += amp * periodic_noise(size, cells, rng)
        norm += amp
        amp *= 0.5
        cells *= 2
    return total / norm


def normalise(a: np.ndarray) -> np.ndarray:
    a = (a - a.min()) / max(1e-6, a.max() - a.min())
    return a


def save_cloud_noise() -> None:
    n = normalise(fbm(256, 4, 6, RNG))
    Image.fromarray((n * 255).astype(np.uint8), "L").save(os.path.join(HERE, "cloud_noise.png"))


def save_asphalt() -> None:
    n = normalise(fbm(256, 8, 4, RNG))
    speckle = RNG.normal(0.0, 0.06, (256, 256))
    v = np.clip(0.55 + 0.25 * (n - 0.5) + speckle, 0.0, 1.0)
    Image.fromarray((v * 255).astype(np.uint8), "L").save(os.path.join(HERE, "asphalt.png"))


def leaf_texture(w: int, h: int, base: tuple, var: float) -> np.ndarray:
    noise = normalise(fbm(max(w, h), 8, 3, RNG))[:h, :w]
    shade = 0.75 + 0.5 * noise + RNG.normal(0.0, var, (h, w))
    rgb = np.stack([np.clip(base[k] * shade, 0, 255) for k in range(3)], axis=-1)
    return rgb


def draw_pine(img: Image.Image, ox: int) -> None:
    tex = leaf_texture(256, 256, (38, 74, 42), 0.05)
    mask = Image.new("L", (256, 256), 0)
    d = ImageDraw.Draw(mask)
    top = 14
    for k in range(7):
        y = top + k * 30
        half = 18 + k * 9
        d.polygon([(128, y), (128 - half, y + 46), (128 + half, y + 46)], fill=255)
    d.rectangle([122, 200, 134, 250], fill=255)
    tile = Image.fromarray(tex.astype(np.uint8), "RGB").convert("RGBA")
    tile.putalpha(mask)
    img.paste(tile, (ox, 0), tile)
    trunk = ImageDraw.Draw(img)
    trunk.rectangle([ox + 124, 200, ox + 132, 255], fill=(92, 66, 44, 255))


def draw_olive(img: Image.Image, ox: int) -> None:
    tex = leaf_texture(256, 256, (110, 128, 88), 0.09)
    mask = Image.new("L", (256, 256), 0)
    d = ImageDraw.Draw(mask)
    for _ in range(9):
        cx = 128 + RNG.normal(0, 22)
        cy = 96 + RNG.normal(0, 18)
        rx = RNG.uniform(38, 56)
        ry = RNG.uniform(30, 44)
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    tile = Image.fromarray(tex.astype(np.uint8), "RGB").convert("RGBA")
    tile.putalpha(mask)
    img.paste(tile, (ox, 0), tile)
    trunk = ImageDraw.Draw(img)
    trunk.polygon([(ox + 118, 150), (ox + 138, 150), (ox + 134, 250), (ox + 122, 250)], fill=(104, 88, 70, 255))


def draw_palm(img: Image.Image, ox: int) -> None:
    trunk = ImageDraw.Draw(img)
    pts = [(128 + 14 * np.sin(t * 2.4), 250 - t * 200) for t in np.linspace(0, 1, 24)]
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        trunk.line([(ox + x0 - 4, y0), (ox + x1 - 4, y1)], fill=(120, 96, 70, 255), width=8)
    cx, cy = ox + pts[-1][0], pts[-1][1]
    green = (58, 110, 48, 255)
    for k in range(9):
        ang = np.pi * (-0.1 + k / 8.0 * 1.2) + np.pi
        length = 90 + RNG.uniform(-12, 12)
        ex = cx + length * np.cos(ang)
        ey = cy + length * np.sin(ang) * 0.5 + 34
        mx = cx + 0.5 * (ex - cx)
        my = cy + 0.5 * (ey - cy) - 26
        pts2 = [(cx, cy), (mx, my - 8), (ex, ey), (mx, my + 16)]
        trunk.polygon(pts2, fill=green)
        trunk.line([(cx, cy), (ex, ey)], fill=(40, 84, 36, 255), width=3)


def draw_shrub(img: Image.Image, ox: int) -> None:
    tex = leaf_texture(256, 256, (120, 118, 72), 0.10)
    mask = Image.new("L", (256, 256), 0)
    d = ImageDraw.Draw(mask)
    for _ in range(14):
        cx = 128 + RNG.normal(0, 46)
        cy = 190 + RNG.normal(0, 12)
        rx = RNG.uniform(22, 38)
        ry = RNG.uniform(16, 30)
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    tile = Image.fromarray(tex.astype(np.uint8), "RGB").convert("RGBA")
    tile.putalpha(mask)
    img.paste(tile, (ox, 0), tile)


def save_trees() -> None:
    img = Image.new("RGBA", (1024, 256), (0, 0, 0, 0))
    draw_pine(img, 0)
    draw_olive(img, 256)
    draw_palm(img, 512)
    draw_shrub(img, 768)
    img.save(os.path.join(HERE, "tree_atlas.png"))


def save_digits() -> None:
    font = None
    for path in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"]:
        if os.path.exists(path):
            font = ImageFont.truetype(path, 200)
            break
    if font is None:
        font = ImageFont.load_default(size=200)
    img = Image.new("RGBA", (1280, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for k in range(10):
        ch = str(k)
        box = d.textbbox((0, 0), ch, font=font)
        w = box[2] - box[0]
        h = box[3] - box[1]
        x = k * 128 + (128 - w) // 2 - box[0]
        y = (256 - h) // 2 - box[1]
        d.text((x, y), ch, font=font, fill=(255, 255, 255, 255))
    img.save(os.path.join(HERE, "runway_digits.png"))


if __name__ == "__main__":
    save_cloud_noise()
    save_asphalt()
    save_trees()
    save_digits()
    print("world textures written to", HERE)
