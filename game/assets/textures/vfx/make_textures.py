"""Generates the Knight Wings VFX textures (procedural, no third-party assets).

Run from the repo root:
    uv run --with pillow,numpy python -I game/assets/textures/vfx/make_textures.py game/assets/textures/vfx
"""
import os
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))


def value_noise(size: int, cells: int, gen) -> np.ndarray:
    """Periodic (tileable) smooth value noise in [0, 1]."""
    g = gen.random((cells, cells))
    ys, xs = np.mgrid[0:size, 0:size] / size * cells
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = xs - x0
    fy = ys - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x1 = (x0 + 1) % cells
    y1 = (y0 + 1) % cells
    x0 %= cells
    y0 %= cells
    a = g[y0, x0]
    b = g[y0, x1]
    c = g[y1, x0]
    d = g[y1, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size: int, gen, octaves: int = 5, base: int = 4) -> np.ndarray:
    out = np.zeros((size, size))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        out += amp * value_noise(size, base * (2 ** o), gen)
        total += amp
        amp *= 0.5
    out /= total
    lo, hi = out.min(), out.max()
    return (out - lo) / (hi - lo + 1e-9)


def radial(size: int):
    """Returns (r, theta): r is 0 at the centre and 1 at the edge midpoint."""
    ys, xs = np.mgrid[0:size, 0:size]
    c = (size - 1) / 2.0
    nx = (xs - c) / (size / 2.0)
    ny = (ys - c) / (size / 2.0)
    return np.sqrt(nx * nx + ny * ny), np.arctan2(ny, nx)


def save_rgba(path: str, rgb: np.ndarray, alpha: np.ndarray) -> None:
    rgba = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(path, optimize=True)


def smoke_flipbook(path: str, frames: int = 4) -> None:
    """4x4 grid of soft grey smoke puffs; RGB is luminance so the material supplies the colour."""
    cell = 128
    size = cell * frames
    rgb = np.zeros((size, size, 3))
    alp = np.zeros((size, size))
    r, _ = radial(cell)
    mask = np.clip(1.0 - r, 0, 1) ** 1.4
    for i in range(frames * frames):
        gen = np.random.default_rng(100 + i)
        n = fbm(cell, gen, octaves=5, base=3)
        alpha = np.clip((n * 1.25 - 0.22) * 1.6, 0, 1) * mask
        shade = 0.82 + 0.18 * fbm(cell, gen, octaves=3, base=2)
        y, x = divmod(i, frames)
        sl = (slice(y * cell, (y + 1) * cell), slice(x * cell, (x + 1) * cell))
        rgb[sl] = shade[..., None]
        alp[sl] = alpha
    save_rgba(path, rgb, alp)


def fire_flipbook(path: str, frames: int = 4) -> None:
    """4x4 grid of flame blobs: white-yellow core fading to deep orange. Use additively."""
    cell = 128
    size = cell * frames
    rgb = np.zeros((size, size, 3))
    alp = np.zeros((size, size))
    r, _ = radial(cell)
    core = np.clip(1.0 - r / 0.55, 0, 1) ** 1.2
    edge = np.clip(1.0 - r, 0, 1) ** 1.6
    for i in range(frames * frames):
        gen = np.random.default_rng(300 + i)
        n = fbm(cell, gen, octaves=5, base=3)
        heat = np.clip(core * 1.1 + (n - 0.45) * 0.9 * edge, 0, 1)
        alpha = np.clip((heat - 0.12) * 1.8, 0, 1) * edge ** 0.3
        r_ch = np.clip(0.6 + 0.4 * heat * 1.6, 0, 1)
        g_ch = np.clip(0.15 + 0.85 * heat ** 1.6, 0, 1)
        b_ch = np.clip(0.02 + 0.6 * heat ** 4, 0, 1)
        y, x = divmod(i, frames)
        sl = (slice(y * cell, (y + 1) * cell), slice(x * cell, (x + 1) * cell))
        rgb[sl] = np.dstack([r_ch, g_ch, b_ch])
        alp[sl] = alpha
    save_rgba(path, rgb, alp)


def puff(path: str) -> None:
    """Single soft billboard puff (multimesh smoke trails and dust)."""
    size = 256
    n = fbm(size, np.random.default_rng(11), octaves=6, base=4)
    r, _ = radial(size)
    mask = np.clip(1.0 - r, 0, 1) ** 1.6
    alpha = np.clip(mask * (0.55 + 0.9 * n), 0, 1)
    shade = 0.88 + 0.12 * n
    save_rgba(path, np.dstack([shade, shade, shade]), alpha)


def spark(path: str) -> None:
    size = 64
    r, _ = radial(size)
    a = np.clip(np.exp(-(r / 0.12) ** 2) + np.exp(-(r / 0.55) ** 2) * 0.65, 0, 1)
    ones = np.ones_like(a)
    save_rgba(path, np.dstack([ones, 0.95 * ones, 0.8 * ones]), a)


def glow(path: str) -> None:
    size = 128
    r, _ = radial(size)
    a = np.clip(np.exp(-(r / 0.42) ** 2) * np.clip(1.0 - r, 0, 1) ** 0.2 * 1.1, 0, 1)
    ones = np.ones_like(a)
    save_rgba(path, np.dstack([ones, 0.92 * ones, 0.8 * ones]), a)


def star(path: str) -> None:
    """Six-blade muzzle flash star with a hot centre."""
    size = 256
    r, th = radial(size)
    blades = np.clip(np.cos(3 * th), 0, 1) ** 6 + 0.5 * np.clip(np.cos(3 * th + np.pi / 3), 0, 1) ** 10
    body = np.clip(1.0 - r, 0, 1) ** 1.3 * (0.25 + 0.95 * blades)
    core = np.exp(-(r / 0.09) ** 2)
    a = np.clip(body * 0.9 + core, 0, 1)
    ones = np.ones_like(a)
    rgb = np.dstack([ones, (0.7 + 0.3 * core), (0.35 + 0.65 * core)])
    save_rgba(path, rgb, a)


def noise(path: str) -> None:
    n = fbm(256, np.random.default_rng(42), octaves=6, base=4)
    Image.fromarray((n * 255).astype(np.uint8), "L").save(path, optimize=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    smoke_flipbook(os.path.join(OUT, "smoke_flipbook.png"))
    fire_flipbook(os.path.join(OUT, "fire_flipbook.png"))
    puff(os.path.join(OUT, "puff.png"))
    spark(os.path.join(OUT, "spark.png"))
    glow(os.path.join(OUT, "glow.png"))
    star(os.path.join(OUT, "muzzle_star.png"))
    noise(os.path.join(OUT, "noise.png"))
    print("ok")
