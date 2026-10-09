#!/usr/bin/env python3
"""Synthetic 256 km test map for the terrain renderer (stand-in until real maps exist).

Run from the repo root:
    ~/.local/bin/uv run --with numpy --with pillow tools/make_test_map.py

Writes (same formats as game/autoload/ground.gd, plus colour):
    game/assets/maps/test/height.r16     4096^2 uint16 LE, row 0 = north, col 0 = west
    game/assets/maps/test/landcover.u8   2048^2 uint8 land-cover classes (Ground.LC_*)
    game/assets/maps/test/color.jpg      2048^2 satellite-like colour, row 0 = north
    game/data/maps/test.json             map metadata
Deterministic (fixed seed).
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_DIR = os.path.join(ROOT, "game", "assets", "maps", "test")
META_PATH = os.path.join(ROOT, "game", "data", "maps", "test.json")

N = 4096  # height grid
L = 2048  # landcover / colour grid
SIZE_M = 256000.0
HMIN = -200.0
HMAX = 3200.0
SEA_LEVEL = 0.0

RNG = np.random.default_rng(20260417)

# Land-cover classes (Ground.LC_*)
LC_WATER, LC_TREES, LC_SHRUB, LC_GRASS, LC_CROP, LC_URBAN, LC_BARE, LC_SNOW = range(8)

# Satellite-like base colours (sRGB) per class
PALETTE = {
    LC_WATER: (26, 60, 80),
    LC_TREES: (36, 70, 34),
    LC_SHRUB: (116, 112, 68),
    LC_GRASS: (86, 128, 52),
    LC_CROP: (164, 156, 72),
    LC_URBAN: (148, 144, 138),
    LC_BARE: (168, 140, 104),
    LC_SNOW: (236, 240, 246),
}


def smooth_noise(res, n=N):
    """Smooth noise in [-1, 1]: random lattice of res+1 points, bicubic-upsampled to n x n."""
    lattice = RNG.standard_normal((res + 1, res + 1)).astype(np.float32)
    img = Image.fromarray(lattice).resize((n, n), Image.BICUBIC)
    a = np.asarray(img, dtype=np.float32)
    return a / max(float(np.abs(a).max()), 1e-6)


def fbm(base, octaves, gain=0.5):
    total = np.zeros((N, N), np.float32)
    amp, norm, res = 1.0, 0.0, base
    for _ in range(octaves):
        total += amp * smooth_noise(res)
        norm += amp
        amp *= gain
        res *= 2
    return total / norm


def ridged(base, octaves, gain=0.5):
    """Ridged multifractal in [0, 1]: sharp crests, the classic mountain shape."""
    total = np.zeros((N, N), np.float32)
    weight = np.ones((N, N), np.float32)
    amp, norm, res = 1.0, 0.0, base
    for _ in range(octaves):
        r = 1.0 - np.abs(smooth_noise(res))
        r = r * r * weight
        total += amp * r
        weight = np.clip(r * 2.0, 0.0, 1.0)
        norm += amp
        amp *= gain
        res *= 2
    return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def flatten(h, cx, cz, half_x, half_z, level, feather):
    """Flatten a rectangle (normalized coords, -1..1) to `level` metres with a soft edge."""
    x_idx = np.linspace(-1.0, 1.0, N, dtype=np.float32)
    X = np.broadcast_to(x_idx[None, :], (N, N))
    Z = np.broadcast_to(x_idx[:, None], (N, N))
    dx = np.maximum(np.abs(X - cx) - half_x, 0.0) * (SIZE_M / 2.0)
    dz = np.maximum(np.abs(Z - cz) - half_z, 0.0) * (SIZE_M / 2.0)
    d = np.sqrt(dx * dx + dz * dz)
    w = 1.0 - smoothstep(0.0, feather, d)
    return h * (1.0 - w) + level * w


def build_height():
    x_idx = np.linspace(-1.0, 1.0, N, dtype=np.float32)
    X = np.broadcast_to(x_idx[None, :], (N, N)).copy()
    Z = np.broadcast_to(x_idx[:, None], (N, N)).copy()  # row 0 = north (-1)

    # Continent: land in the east/centre, sea to the west and south-west, one large bay.
    cont = (
        1.0
        - ((X - 0.22) / 0.92) ** 2
        - ((Z + 0.08) / 0.78) ** 2
        + 0.40 * fbm(3, 4)
        + 0.10 * fbm(14, 4)
    ).astype(np.float32)
    land_w = smoothstep(-0.015, 0.02, cont)

    # Lowlands, hills and mountains (mountains concentrated in the north-east).
    mount_field = np.clip(0.55 + 0.6 * fbm(3, 4) - 0.35 * Z + 0.25 * X, 0.0, 1.0)
    lowland = 22.0 + 70.0 * (0.5 + 0.5 * fbm(8, 5))
    hills = 480.0 * ridged(14, 4) ** 1.2 * (0.25 + 0.75 * mount_field)
    mountains = 3600.0 * ridged(5, 6) ** 1.1 * mount_field ** 0.9
    h_land = lowland + hills + mountains
    h_land = h_land * smoothstep(0.0, 0.16, cont) + 2.0 * (1.0 - smoothstep(0.0, 0.16, cont))
    h_land = np.minimum(h_land, 3000.0)

    sea_floor = -6.0 - 190.0 * np.clip(-cont * 3.0, 0.0, 1.0)
    h = land_w * h_land + (1.0 - land_w) * sea_floor

    # Flat runway/airbase on the coastal plain (kept clear of mountains).
    h = flatten(h, 0.10, 0.22, 0.10, 0.030, 74.0, 2500.0)
    return h.astype(np.float32), cont


def build_landcover(h, cont):
    gz, gx = np.gradient(h, SIZE_M / (N - 1))
    slope = np.sqrt(gx * gx + gz * gz)
    # Downsample to the landcover grid.
    h_l = h[::2, ::2]
    slope_l = slope[::2, ::2]
    cont_l = cont[::2, ::2]
    forest = fbm(40, 3)[::2, ::2]
    field = fbm(64, 3)[::2, ::2]
    patch = fbm(10, 3)[::2, ::2]

    lc = np.full((L, L), LC_GRASS, np.uint8)
    lowland = h_l < 260.0
    lc[lowland & (field > 0.15) & (slope_l < 0.06)] = LC_CROP
    lc[(h_l > 60.0) & (h_l < 1500.0) & (forest > -0.05) & (slope_l < 0.5)] = LC_TREES
    lc[(h_l > 40.0) & (patch > 0.2) & (slope_l < 0.7) & (lc == LC_GRASS)] = LC_SHRUB
    lc[(h_l > 1600.0) & (slope_l < 0.3)] = LC_SHRUB
    lc[(h_l > 1900.0) & (slope_l > 0.2)] = LC_BARE
    lc[slope_l > 0.45] = LC_BARE
    lc[(h_l < 6.0) & (cont_l < 0.10) & (h_l >= SEA_LEVEL)] = LC_BARE  # beaches
    lc[h_l > 2350.0 + 120.0 * patch] = LC_SNOW
    lc[h_l < SEA_LEVEL] = LC_WATER

    # Urban patches: a town on the flat coastal plain and a few villages.
    for cx, cz, r in ((0.10, 0.22, 0.025), (0.46, 0.05, 0.02), (-0.05, -0.30, 0.018), (0.55, 0.40, 0.015)):
        xs = np.linspace(-1.0, 1.0, L, dtype=np.float32)
        X = xs[None, :]
        Z = xs[:, None]
        m = ((X - cx) ** 2 + (Z - cz) ** 2) < r * r
        lc[m & (h_l > SEA_LEVEL)] = LC_URBAN
    return lc


def build_color(h, lc):
    h_l = h[::2, ::2]
    gz, gx = np.gradient(h_l, SIZE_M / (L - 1))
    nrm = np.stack([-gx, np.ones_like(gx), -gz], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    light = np.array([-0.45, 0.6, -0.65], np.float32)
    light /= np.linalg.norm(light)
    shade = np.clip(nrm @ light, 0.0, 1.0)

    rgb = np.zeros((L, L, 3), np.float32)
    for cls, col in PALETTE.items():
        rgb[lc == cls] = np.array(col, np.float32)
    # Fine colour variation (multi-scale) so the far texture is not flat.
    var = 0.5 * fbm(128, 2)[::2, ::2] + 0.5 * fbm(512, 2)[::2, ::2]
    rgb *= (1.0 + 0.10 * var)[..., None]
    rgb *= (0.42 + 0.78 * shade)[..., None]
    # Bare/rock slopes are greyer, snow bright.
    rock = (lc == LC_BARE) & (h_l > 600.0)
    rgb[rock] = rgb[rock] * 0.6 + np.array([120, 116, 112], np.float32) * 0.4
    return np.clip(rgb, 0, 255).astype(np.uint8)


def main():
    os.makedirs(MAP_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(META_PATH), exist_ok=True)

    h, cont = build_height()
    q = np.clip((h - HMIN) / (HMAX - HMIN), 0.0, 1.0)
    q16 = np.round(q * 65535.0).astype("<u2")
    with open(os.path.join(MAP_DIR, "height.r16"), "wb") as f:
        f.write(q16.tobytes())

    lc = build_landcover(h, cont)
    with open(os.path.join(MAP_DIR, "landcover.u8"), "wb") as f:
        f.write(lc.tobytes())

    rgb = build_color(h, lc)
    Image.fromarray(rgb).save(os.path.join(MAP_DIR, "color.jpg"), quality=90)

    meta = {
        "id": "test",
        "name": "Synthetic test map",
        "generator": "tools/make_test_map.py",
        "size_m": SIZE_M,
        "sea_level": SEA_LEVEL,
        "height_min": HMIN,
        "height_max": HMAX,
        "height_n": N,
        "landcover_n": L,
        "height_file": "res://assets/maps/test/height.r16",
        "landcover_file": "res://assets/maps/test/landcover.u8",
        "color_file": "res://assets/maps/test/color.jpg",
    }
    with open(META_PATH, "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print("height range %.1f .. %.1f m, land fraction %.2f" % (h.min(), h.max(), float((h > SEA_LEVEL).mean())))


if __name__ == "__main__":
    main()
