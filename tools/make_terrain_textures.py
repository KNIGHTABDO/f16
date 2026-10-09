#!/usr/bin/env python3
"""Procedural, seamless terrain detail textures for terrain.gdshader.

Writes 8 layers x (albedo, normal) at 1024^2 to game/core/world/terrain_textures/{albedo,normal}/<layer>.jpg.
Every texture tiles on both axes (periodic FFT noise, periodic Voronoi cells, wrap-around gradients), so the
shader can repeat them at any scale. Deterministic (fixed seed). No third-party images are used.

Run from the repo root (numpy + Pillow only):
    python3 tools/make_terrain_textures.py

Layer order = terrain.gd LAYER_NAMES = the shader's layer index: grass, dry, farm, forest, rock, sand, snow, urban.
Albedo is sRGB and un-lit (the shader lights it and grades the satellite tint on top).
"""
from pathlib import Path

import numpy as np
from PIL import Image

N = 1024
SEED = 20261009
ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "game" / "core" / "world" / "terrain_textures"
rng = np.random.default_rng(SEED)

_yy, _xx = np.mgrid[0:N, 0:N].astype(np.float32)
_freq = np.fft.fftfreq(N).astype(np.float32) * N  # cycles per tile for each FFT bin
_FY, _FX = np.meshgrid(_freq, _freq, indexing="ij")


def noise(cut: float, aniso: tuple[float, float] = (1.0, 1.0)) -> np.ndarray:
	"""Periodic band-limited noise in [0, 1]. `cut` = Gaussian cutoff in cycles per tile (higher = finer)."""
	spec = np.fft.fft2(rng.standard_normal((N, N)).astype(np.float32))
	gain = np.exp(-0.5 * ((_FX / aniso[0]) ** 2 + (_FY / aniso[1]) ** 2) / (cut * cut))
	field = np.fft.ifft2(spec * gain).real.astype(np.float32)
	field /= 4.0 * field.std() + 1e-9
	return np.clip(0.5 + 0.5 * field, 0.0, 1.0)


def fbm(cuts: tuple[float, ...], decay: float = 0.6) -> np.ndarray:
	"""Sum of periodic noise octaves, renormalised to [0, 1]."""
	out = np.zeros((N, N), np.float32)
	amp = 1.0
	total = 0.0
	for c in cuts:
		out += amp * (noise(c) - 0.5)
		total += amp
		amp *= decay
	return np.clip(0.5 + out / total, 0.0, 1.0)


def warp(img: np.ndarray, dx: np.ndarray, dy: np.ndarray) -> np.ndarray:
	"""img sampled at (x + dx, y + dy): bilinear with wrap-around, offsets in texels."""
	x = np.mod(_xx + dx, N)
	y = np.mod(_yy + dy, N)
	x0 = np.floor(x).astype(np.int32)
	y0 = np.floor(y).astype(np.int32)
	fx = x - x0
	fy = y - y0
	x1 = (x0 + 1) % N
	y1 = (y0 + 1) % N
	top = img[y0, x0] * (1.0 - fx) + img[y0, x1] * fx
	bot = img[y1, x0] * (1.0 - fx) + img[y1, x1] * fx
	return top * (1.0 - fy) + bot * fy


def cells(count: int) -> tuple[np.ndarray, np.ndarray]:
	"""Periodic jittered-grid Voronoi. Returns (distance to the nearest feature point in cell units,
	random value in [0, 1] of that point's cell)."""
	cs = N / count
	jx = rng.random((count, count)).astype(np.float32)
	jy = rng.random((count, count)).astype(np.float32)
	val = rng.random((count, count)).astype(np.float32)
	ci = np.floor(_xx / cs).astype(np.int32)
	cj = np.floor(_yy / cs).astype(np.int32)
	best = np.full((N, N), 1e9, np.float32)
	bval = np.zeros((N, N), np.float32)
	for dj in (-1, 0, 1):
		for di in (-1, 0, 1):
			cc = ci + di
			rr = cj + dj
			wc = np.floor_divide(cc, count)
			wr = np.floor_divide(rr, count)
			cc = cc - wc * count
			rr = rr - wr * count
			px = (cc + jx[rr, cc]) * cs + wc * N
			py = (rr + jy[rr, cc]) * cs + wr * N
			d = (_xx - px) ** 2 + (_yy - py) ** 2
			closer = d < best
			best = np.where(closer, d, best)
			bval = np.where(closer, val[rr, cc], bval)
	return np.sqrt(best) / cs, bval


def ramp(t: np.ndarray, stops: list[tuple[float, tuple[int, int, int]]]) -> np.ndarray:
	"""Colour ramp: t in [0, 1] -> sRGB 0..1 RGB, linear between (position, 0..255 colour) stops."""
	pos = np.array([p for p, _ in stops], np.float32)
	cols = np.array([c for _, c in stops], np.float32)
	out = np.empty(t.shape + (3,), np.float32)
	for k in range(3):
		out[..., k] = np.interp(t, pos, cols[:, k])
	return out / 255.0


def grass():
	base = fbm((3, 12, 40))
	blade = noise(70, aniso=(1.0, 0.2))  # streaks along y, like blades
	speck = noise(180)
	t = np.clip(0.5 * base + 0.35 * blade + 0.15 * speck, 0.0, 1.0)
	alb = ramp(t, [(0.0, (56, 80, 32)), (0.5, (104, 128, 52)), (0.85, (150, 150, 74)), (1.0, (170, 158, 92))])
	alb *= (0.88 + 0.24 * speck)[..., None]
	return alb, 0.6 * t + 0.4 * blade, 2.0


def dry():
	soil = fbm((4, 14, 48))
	f1, pval = cells(40)
	pebble = (1.0 - np.clip((f1 - 0.2) / 0.15, 0.0, 1.0)) * (pval > 0.45)
	clump = np.clip((noise(60) - 0.58) / 0.15, 0.0, 1.0)
	alb = ramp(soil, [(0.0, (138, 116, 78)), (0.5, (176, 152, 108)), (1.0, (204, 184, 140))])
	stone = ramp(pval, [(0.0, (120, 110, 96)), (1.0, (196, 186, 166))])
	alb = alb * (1.0 - pebble[..., None]) + stone * pebble[..., None]
	olive = np.array([88, 98, 56], np.float32) / 255.0
	alb = alb * (1.0 - clump[..., None]) + olive * clump[..., None]
	return alb, 0.5 * soil + 0.5 * pebble, 3.0


def farm():
	wob = (fbm((5, 18)) - 0.5) * 36.0
	phase = 2.0 * np.pi * 36.0 * (_yy + wob) / N  # 36 furrows per tile, wobbling
	furrow = 0.5 + 0.5 * np.cos(phase)
	soil = fbm((5, 16, 50))
	alb = ramp(soil, [(0.0, (92, 60, 44)), (0.5, (124, 84, 60)), (1.0, (158, 112, 80))])
	alb *= (0.8 + 0.26 * furrow)[..., None]
	crop = np.clip((fbm((2, 6)) - 0.62) / 0.1, 0.0, 1.0)
	green = ramp(soil, [(0.0, (84, 104, 52)), (1.0, (122, 138, 66))])
	alb = alb * (1.0 - crop[..., None]) + green * crop[..., None]
	return alb, 0.7 * furrow + 0.3 * soil, 2.0


def forest():
	f1, val = cells(7)
	crown = np.clip((0.5 - f1) / 0.12, 0.0, 1.0)
	shade = 1.0 - 0.45 * np.clip(f1 / 0.5, 0.0, 1.0) ** 2
	tone = ramp(val, [(0.0, (30, 52, 22)), (1.0, (72, 100, 46))])
	floor = ramp(fbm((4, 20)), [(0.0, (20, 30, 14)), (1.0, (46, 52, 28))])
	alb = floor * (1.0 - crown[..., None]) + tone * (shade * crown)[..., None]
	hgt = 0.7 * crown * (1.0 - f1) + 0.3 * fbm((6, 24))
	return alb, hgt, 2.5


def rock():
	strata = 0.5 + 0.5 * np.sin(2.0 * np.pi * (_yy + (fbm((3, 10)) - 0.5) * 160.0) * 24.0 / N)
	body = fbm((3, 9, 30))
	pits = noise(110)
	t = np.clip(0.55 * body + 0.3 * strata + 0.15 * pits, 0.0, 1.0)
	alb = ramp(t, [(0.0, (88, 80, 70)), (0.5, (134, 120, 102)), (1.0, (178, 164, 142))])
	crack = (1.0 - np.abs(2.0 * fbm((4, 12, 36)) - 1.0)) ** 8
	alb *= (1.0 - 0.35 * crack)[..., None]
	return alb, t - 0.5 * crack, 3.0


def sand():
	dune = fbm((2, 5))
	ripple_phase = 2.0 * np.pi * (40.0 * _xx + 6.0 * _yy + 10.0 * (dune - 0.5) * N * 0.05) / N
	ripple = 0.5 + 0.5 * np.cos(ripple_phase)
	grain = noise(200)
	t = np.clip(0.55 * dune + 0.25 * ripple + 0.2 * grain, 0.0, 1.0)
	alb = ramp(t, [(0.0, (180, 144, 98)), (0.5, (210, 176, 124)), (1.0, (232, 208, 160))])
	return alb, 0.6 * ripple + 0.4 * dune, 1.2


def snow():
	body = fbm((3, 10, 30))
	drift = noise(40, aniso=(1.0, 0.15))
	t = np.clip(0.7 * body + 0.3 * drift, 0.0, 1.0)
	alb = ramp(t, [(0.0, (184, 196, 212)), (0.5, (226, 234, 242)), (1.0, (248, 250, 252))])
	return alb, drift, 0.8


def urban():
	block = 256
	gap = 12
	bi = (_xx // block).astype(np.int32)
	bj = (_yy // block).astype(np.int32)
	xi = np.mod(_xx, block)
	yi = np.mod(_yy, block)
	inside = (xi > gap) & (xi < block - gap) & (yi > gap) & (yi < block - gap)
	roofs = np.array(
		[(150, 108, 86), (124, 120, 116), (178, 172, 160), (96, 92, 92), (164, 130, 96)], np.float32) / 255.0
	pick = rng.integers(0, len(roofs), (N // block, N // block))
	tint = rng.uniform(0.85, 1.08, (N // block, N // block)).astype(np.float32)
	roof = roofs[pick[bj, bi]] * tint[bj, bi][..., None]
	roof = roof * (0.85 + 0.3 * fbm((6, 22)))[..., None]
	seams = 0.92 + 0.08 * np.sign(np.sin(2.0 * np.pi * yi / 32.0))
	roof = roof * seams[..., None]
	street = ramp(noise(90), [(0.0, (52, 52, 56)), (1.0, (84, 82, 84))])
	alb = np.where(inside[..., None], roof, street)
	hgt = inside.astype(np.float32) * 0.8 + 0.1 * fbm((6, 20))
	return alb, hgt, 4.0


LAYERS = {
	"grass": grass,
	"dry": dry,
	"farm": farm,
	"forest": forest,
	"rock": rock,
	"sand": sand,
	"snow": snow,
	"urban": urban,
}


def normal_map(hgt: np.ndarray, strength: float) -> np.ndarray:
	"""Tangent-space normal map from a periodic height field (wrap-around central differences)."""
	dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5
	dy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5
	nx = -dx * strength * N / 64.0
	ny = -dy * strength * N / 64.0
	nz = np.ones_like(hgt)
	inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
	n = np.stack([nx * inv, ny * inv, nz * inv], axis=-1)
	return np.clip((n * 0.5 + 0.5) * 255.0 + 0.5, 0.0, 255.0).astype(np.uint8)


def main() -> None:
	(OUT_DIR / "albedo").mkdir(parents=True, exist_ok=True)
	(OUT_DIR / "normal").mkdir(parents=True, exist_ok=True)
	for name, make in LAYERS.items():
		alb, hgt, strength = make()
		hgt = hgt.astype(np.float32)
		albedo = np.clip(alb * 255.0 + 0.5, 0.0, 255.0).astype(np.uint8)
		Image.fromarray(albedo, "RGB").save(OUT_DIR / "albedo" / f"{name}.jpg", quality=92, subsampling=0)
		Image.fromarray(normal_map(hgt, strength), "RGB").save(
			OUT_DIR / "normal" / f"{name}.jpg", quality=92, subsampling=0)
		print(f"{name}: mean {albedo.reshape(-1, 3).mean(axis=0).round(0).tolist()}")


if __name__ == "__main__":
	main()
