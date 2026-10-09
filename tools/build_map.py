#!/usr/bin/env python3
"""Knight Wings map pipeline: free real-world geodata -> game map files.

Writes, per map id in tools/maps.json:
  game/assets/maps/<id>/height.r16    uint16 LE, N*N, row 0 = north, col 0 = west (see game/autoload/ground.gd)
  game/assets/maps/<id>/landcover.u8  uint8 land-cover classes (Ground.LC_*), same orientation
  game/assets/maps/<id>/color.jpg     8192^2 satellite colour, graded
  game/data/maps/<id>.json            metadata: airports, places, roads, spawn, ...

Sources (all free, public, no login):
  Height       Copernicus DEM GLO-30 (S3, 1x1 deg COG tiles; missing tile = open sea)
  Land cover   ESA WorldCover 2021 v200 (S3, 3x3 deg COG tiles)
  Colour       EOX Sentinel-2 cloudless 2023 (WMTS, zoom 13)
  Airports, places, roads   OpenStreetMap via the Overpass API

Run from anywhere (tools/cache/ holds downloads and is gitignored; reruns reuse it):
  ~/.local/bin/uv run --with numpy --with rasterio --with pillow --with requests --with scipy \
      python tools/build_map.py [--maps gibraltar atlas] [--no-previews]
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import math
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import rasterio
import requests
from PIL import Image
from rasterio.windows import Window
from scipy import ndimage

TOOLS_DIR = Path(__file__).resolve().parent
ROOT = TOOLS_DIR.parent
CACHE = TOOLS_DIR / "cache"
ASSETS_DIR = ROOT / "game" / "assets" / "maps"
DATA_DIR = ROOT / "game" / "data" / "maps"
PREVIEW_DIR = Path("/tmp")

# ---- Projection (must match the brief: local flat, +X east, -Z north) ----
METERS_PER_DEG_LAT = 110574.0
METERS_PER_DEG_LON_EQUATOR = 111320.0

# ---- Output grids ----
HEIGHT_N = 4096
LANDCOVER_N = 4096
COLOR_N = 8192
BLOCK_ROWS = 64  # output rows per processing block for height/landcover
COLOR_BLOCK_ROWS = 256

# ---- Source resolutions (degrees per pixel) ----
DEM_RES = 1.0 / 3600.0  # Copernicus GLO-30: 1 arc-second
DEM_PHASE = 0.5  # GLO-30 is pixel-is-point: cell edges sit half a cell off the integer degrees
WC_RES = 1.0 / 12000.0  # WorldCover: 1/12000 degree (~10 m)
SOURCE_PAD_DEG = 0.01  # extra margin around the map when cropping sources
BAND_PAD_DEG = 0.002

# ---- Land cover classes (game/autoload/ground.gd) ----
LC_WATER, LC_TREES, LC_SHRUB, LC_GRASS, LC_CROP, LC_URBAN, LC_BARE, LC_SNOW, LC_WETLAND = range(9)
WORLDCOVER_TO_LC = {
    10: LC_TREES, 20: LC_SHRUB, 30: LC_GRASS, 40: LC_CROP, 50: LC_URBAN, 60: LC_BARE,
    70: LC_SNOW, 80: LC_WATER, 90: LC_WETLAND, 95: LC_WETLAND, 100: LC_GRASS,
}
WC_LUT = np.zeros(256, dtype=np.uint8)  # nodata / ocean -> water
for _code, _cls in WORLDCOVER_TO_LC.items():
    WC_LUT[_code] = _cls
LC_PALETTE = np.array([
    (30, 70, 110), (34, 100, 40), (120, 140, 60), (150, 180, 80), (200, 180, 90),
    (190, 80, 80), (200, 170, 120), (240, 240, 250), (60, 140, 130),
], dtype=np.uint8)

# ---- Height model ----
SEA_NEAR_DEPTH_M = -2.0  # depth at the coast
SEA_FAR_DEPTH_M = -60.0  # depth at SEA_FULL_DEPTH_DIST_M offshore
SEA_FULL_DEPTH_DIST_M = 3000.0
LAND_MIN_HEIGHT_M = 0.5  # land the DEM puts at or below sea level is lifted just above it

# ---- Airports / runways ----
RUNWAY_MIN_LENGTH_M = 1500.0
RUNWAY_DEFAULT_WIDTH_M = 45.0
RUNWAY_BLEND_M = 300.0
RUNWAY_SAMPLE_STEP_M = 50.0
AIRPORT_MATCH_RADIUS_M = 10000.0

# ---- Roads ----
ROAD_SIMPLIFY_M = 50.0
ROAD_MAX_POLYLINES = 400

# ---- Colour grading ----
GRADE_CONTRAST = 1.08
GRADE_SATURATION = 1.12
GRADE_WB_CLAMP = (0.85, 1.15)
SEA_TINT = np.array([34.0, 48.0, 58.0], dtype=np.float32)  # neutral deep blue-grey
SEA_TINT_MIX = 0.85
JPEG_QUALITY = 90
EOX_ZOOM = 13
EOX_URL = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2023_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg"
OVERPASS_URL = "https://overpass-api.de/api/interpreter"

DEM_URL = ("https://copernicus-dem-30m.s3.amazonaws.com/{name}/{name}.tif")
WC_URL = ("https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/{name}.tif")

ATTRIBUTION = ("Copernicus DEM (c) DLR/ESA; ESA WorldCover; Sentinel-2 cloudless by EOX; "
               "(c) OpenStreetMap contributors")
USER_AGENT = "knight-wings-map-builder/1.0 (personal use)"

GDAL_ENV = {
    "GDAL_DISABLE_READDIR_ON_OPEN": "EMPTY_DIR",
    "CPL_VSIL_CURL_ALLOWED_EXTENSIONS": ".tif",
    "GDAL_HTTP_MAX_RETRY": "8",
    "GDAL_HTTP_RETRY_DELAY": "5",
    "GDAL_HTTP_TIMEOUT": "300",
    "GDAL_CACHEMAX": 512,  # MB; rasterio requires an int here
}


def log(msg: str) -> None:
    print(time.strftime("%H:%M:%S") + " " + msg, flush=True)


def snap_down(v: float, res: float, phase: float = 0.0) -> float:
    """Largest source-grid cell edge <= v. phase = offset of the source edges, in cells."""
    return (math.floor(v / res - phase + 1e-9) + phase) * res


def snap_up(v: float, res: float, phase: float = 0.0) -> float:
    """Smallest source-grid cell edge >= v."""
    return (math.ceil(v / res - phase - 1e-9) + phase) * res


def grid_offset(v: float) -> int:
    r = round(v)
    if abs(v - r) > 1e-3:
        raise ValueError(f"source grid misaligned by {v - r} pixels")
    return int(r)


# ======================================================================
# Projection
# ======================================================================
class Projection:
    """x_east = (lon-lon0)*111320*cos(lat0), z = -(lat-lat0)*110574 (metres)."""

    def __init__(self, lat0: float, lon0: float, size_m: float):
        self.lat0 = float(lat0)
        self.lon0 = float(lon0)
        self.size = float(size_m)
        self.half = self.size / 2.0
        self.kx = METERS_PER_DEG_LON_EQUATOR * math.cos(math.radians(self.lat0))
        self.ky = METERS_PER_DEG_LAT

    def grid(self, n: int) -> np.ndarray:
        """Coordinates of the n samples of a grid, corner-aligned like ground.gd (-half + i*size/(n-1))."""
        return -self.half + np.arange(n, dtype=np.float64) * (self.size / (n - 1))

    def lon_of_x(self, x):
        return self.lon0 + np.asarray(x, dtype=np.float64) / self.kx

    def lat_of_z(self, z):
        return self.lat0 - np.asarray(z, dtype=np.float64) / self.ky

    def x_of_lon(self, lon):
        return (np.asarray(lon, dtype=np.float64) - self.lon0) * self.kx

    def z_of_lat(self, lat):
        return -(np.asarray(lat, dtype=np.float64) - self.lat0) * self.ky

    def bounds(self) -> tuple[float, float, float, float]:
        """(west, south, east, north) of the square map."""
        return (self.lon_of_x(-self.half), self.lat_of_z(self.half),
                self.lon_of_x(self.half), self.lat_of_z(-self.half))

    def padded_bounds(self, pad: float) -> tuple[float, float, float, float]:
        w, s, e, n = self.bounds()
        return (w - pad, s - pad, e + pad, n + pad)


def bilinear_grid(grid: np.ndarray, fx: np.ndarray, fz: np.ndarray) -> np.ndarray:
    """Bilinear sample of a 2-D grid at fractional indices fx (column) and fz (row). Clamped at the edges."""
    nr, nc = grid.shape
    c0 = np.clip(np.floor(fx).astype(np.int64), 0, nc - 2)
    r0 = np.clip(np.floor(fz).astype(np.int64), 0, nr - 2)
    tc = np.clip(fx - c0, 0.0, 1.0)
    tr = np.clip(fz - r0, 0.0, 1.0)
    v00 = grid[r0[:, None], c0[None, :]]
    v01 = grid[r0[:, None], c0[None, :] + 1]
    v10 = grid[r0[:, None] + 1, c0[None, :]]
    v11 = grid[r0[:, None] + 1, c0[None, :] + 1]
    top = v00 + (v01 - v00) * tc[None, :]
    bot = v10 + (v11 - v10) * tc[None, :]
    return top + (bot - top) * tr[:, None]


def sample_grid_xz(grid: np.ndarray, proj: Projection, x: np.ndarray, z: np.ndarray) -> np.ndarray:
    """Bilinear sample of a corner-aligned N*N grid at map metres (x, z) (1-D arrays, same length)."""
    n = grid.shape[0]
    step = proj.size / (n - 1)
    fx = (x + proj.half) / step
    fz = (z + proj.half) / step
    c0 = np.clip(np.floor(fx).astype(np.int64), 0, n - 2)
    r0 = np.clip(np.floor(fz).astype(np.int64), 0, n - 2)
    tc = np.clip(fx - c0, 0.0, 1.0)
    tr = np.clip(fz - r0, 0.0, 1.0)
    v00 = grid[r0, c0]
    v01 = grid[r0, c0 + 1]
    v10 = grid[r0 + 1, c0]
    v11 = grid[r0 + 1, c0 + 1]
    top = v00 + (v01 - v00) * tc
    bot = v10 + (v11 - v10) * tc
    return top + (bot - top) * tr


# ======================================================================
# Source tiles: cropped windows of remote COGs, cached as local GeoTIFFs
# ======================================================================
@dataclass
class Crop:
    path: Path
    left: float
    top: float
    res: float
    width: int
    height: int


def dem_tile_name(lat_sw: int, lon_sw: int) -> str:
    ns = "N" if lat_sw >= 0 else "S"
    ew = "E" if lon_sw >= 0 else "W"
    return f"Copernicus_DSM_COG_10_{ns}{abs(lat_sw):02d}_00_{ew}{abs(lon_sw):03d}_00_DEM"


def wc_tile_name(lat_sw: int, lon_sw: int) -> str:
    ns = "N" if lat_sw >= 0 else "S"
    ew = "E" if lon_sw >= 0 else "W"
    return f"ESA_WorldCover_10m_2021_v200_{ns}{abs(lat_sw):02d}{ew}{abs(lon_sw):03d}_Map"


def tiles_for_bounds(bounds, step: int):
    west, south, east, north = bounds
    lat0 = math.floor(south / step) * step
    lon0 = math.floor(west / step) * step
    out = []
    lat = lat0
    while lat < north:
        lon = lon0
        while lon < east:
            out.append((int(lat), int(lon)))
            lon += step
        lat += step
    return out


def remote_exists(url: str) -> bool:
    for attempt in range(5):
        try:
            r = requests.head(url, timeout=60, allow_redirects=True, headers={"User-Agent": USER_AGENT})
            if r.status_code == 200:
                return True
            if r.status_code in (403, 404):  # S3 answers 403 for absent keys
                return False
        except requests.RequestException:
            pass
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"cannot reach {url}")


def pixel_window(transform, bounds, width: int, height: int) -> Window | None:
    west, south, east, north = bounds
    inv = ~transform
    ca, ra = inv * (west, north)
    cb, rb = inv * (east, south)
    c0 = max(0, math.floor(min(ca, cb)))
    c1 = min(width, math.ceil(max(ca, cb)))
    r0 = max(0, math.floor(min(ra, rb)))
    r1 = min(height, math.ceil(max(ra, rb)))
    if c1 <= c0 or r1 <= r0:
        return None
    return Window(c0, r0, c1 - c0, r1 - r0)


def crop_remote(url: str, bounds, out_path: Path) -> None:
    """Copy the part of a remote GeoTIFF inside bounds to out_path (strips read over HTTP range requests)."""
    tmp = out_path.parent / (out_path.name + ".part")
    strip = 1024
    with rasterio.Env(**GDAL_ENV):
        with rasterio.open("/vsicurl/" + url) as src:
            win = pixel_window(src.transform, bounds, src.width, src.height)
            if win is None:
                raise ValueError("crop window is empty")
            profile = dict(driver="GTiff", width=int(win.width), height=int(win.height), count=1,
                           dtype=src.dtypes[0], crs=src.crs, transform=src.window_transform(win),
                           nodata=src.nodata, tiled=True, blockxsize=512, blockysize=512,
                           compress="deflate")
            with rasterio.open(tmp, "w", **profile) as dst:
                for r0 in range(0, int(win.height), strip):
                    rows = min(strip, int(win.height) - r0)
                    data = src.read(1, window=Window(win.col_off, win.row_off + r0, win.width, rows))
                    dst.write(data, 1, window=Window(0, r0, win.width, rows))
    os.replace(tmp, out_path)


def fetch_crop(name: str, url: str, bounds, cache_dir: Path) -> Path | None:
    """Ensure the crop exists in cache_dir. Returns None for tiles that do not exist (open sea)."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    out = cache_dir / f"{name}.tif"
    missing = cache_dir / f"{name}.missing"
    if out.exists():
        return out
    if missing.exists():
        return None
    if not remote_exists(url):
        missing.touch()
        return None
    for attempt in range(3):
        try:
            t0 = time.time()
            crop_remote(url, bounds, out)
            log(f"  fetched {name} crop in {time.time() - t0:.0f}s ({out.stat().st_size / 1e6:.1f} MB)")
            return out
        except Exception as exc:  # noqa: BLE001 - retry any transient GDAL/HTTP failure
            log(f"  retry {name} ({attempt + 1}/3): {exc}")
            time.sleep(10 * (attempt + 1))
    raise RuntimeError(f"failed to fetch {name}")


def load_crops(paths: list[Path]) -> list[Crop]:
    crops = []
    for p in paths:
        with rasterio.open(p) as ds:
            t = ds.transform
            if abs(t.a + t.e) > 1e-15 or t.b != 0 or t.d != 0:
                raise ValueError(f"unexpected transform in {p}")
            crops.append(Crop(p, t.c, t.f, t.a, ds.width, ds.height))
    return crops


def read_band(crops: list[Crop], left: float, top: float, res: float, ncols: int, nrows: int,
              dtype, fill: int = 0) -> np.ndarray:
    """Assemble a band of the source grid (left, top, res) from the crops. Uncovered pixels = fill."""
    out = np.full((nrows, ncols), fill, dtype=dtype)
    for c in crops:
        col_off = grid_offset((c.left - left) / res)
        row_off = grid_offset((top - c.top) / res)
        bc0, bc1 = max(0, col_off), min(ncols, col_off + c.width)
        br0, br1 = max(0, row_off), min(nrows, row_off + c.height)
        if bc0 >= bc1 or br0 >= br1:
            continue
        win = Window(bc0 - col_off, br0 - row_off, bc1 - bc0, br1 - br0)
        with rasterio.open(c.path) as ds:
            out[br0:br1, bc0:bc1] = ds.read(1, window=win)
    return out


def fetch_sources(map_id: str, bounds) -> tuple[list[Crop], list[Crop]]:
    """Downloads (only the needed windows) of every DEM and WorldCover tile the map touches."""
    jobs = []
    dem_dir = CACHE / "dem" / map_id
    wc_dir = CACHE / "worldcover" / map_id
    for lat, lon in tiles_for_bounds(bounds, 1):
        name = dem_tile_name(lat, lon)
        jobs.append(("dem", name, DEM_URL.format(name=name), (lon, lat, lon + 1, lat + 1), dem_dir))
    for lat, lon in tiles_for_bounds(bounds, 3):
        name = wc_tile_name(lat, lon)
        jobs.append(("wc", name, WC_URL.format(name=name), (lon, lat, lon + 3, lat + 3), wc_dir))
    # Each job wants only the map's bounds intersected with its own tile.
    results: dict[str, list[Path]] = {"dem": [], "wc": []}
    log(f"[{map_id}] sources: {sum(j[0] == 'dem' for j in jobs)} DEM tiles, "
        f"{sum(j[0] == 'wc' for j in jobs)} WorldCover tiles")

    def run(job):
        kind, name, url, tile_bounds, cache_dir = job
        west, south, east, north = bounds
        inter = (max(west, tile_bounds[0]), max(south, tile_bounds[1]),
                 min(east, tile_bounds[2]), min(north, tile_bounds[3]))
        if inter[2] <= inter[0] or inter[3] <= inter[1]:
            return kind, None
        return kind, fetch_crop(name, url, inter, cache_dir)

    with cf.ThreadPoolExecutor(max_workers=4) as pool:
        for kind, path in pool.map(run, jobs):
            if path is not None:
                results[kind].append(path)
    dem = load_crops(sorted(results["dem"]))
    wc = load_crops(sorted(results["wc"]))
    log(f"[{map_id}] using {len(dem)} DEM crops (rest of tiles = sea), {len(wc)} WorldCover crops")
    return dem, wc


# ======================================================================
# Height and land cover grids
# ======================================================================
def build_raw_height(proj: Projection, crops: list[Crop]) -> np.ndarray:
    """Bilinear Copernicus DEM sampled on the N*N grid. Nodata and missing tiles -> 0 (sea)."""
    n = HEIGHT_N
    xs = proj.grid(n)
    zs = proj.grid(n)
    lons = proj.lon_of_x(xs)
    lats = proj.lat_of_z(zs)
    out = np.empty((n, n), dtype=np.float32)
    west = snap_down(lons[0] - BAND_PAD_DEG, DEM_RES, DEM_PHASE)
    east = snap_up(lons[-1] + BAND_PAD_DEG, DEM_RES, DEM_PHASE)
    for j0 in range(0, n, BLOCK_ROWS):
        j1 = min(n, j0 + BLOCK_ROWS)
        north = snap_up(lats[j0] + BAND_PAD_DEG, DEM_RES, DEM_PHASE)
        south = snap_down(lats[j1 - 1] - BAND_PAD_DEG, DEM_RES, DEM_PHASE)
        ncols = round((east - west) / DEM_RES)
        nrows = round((north - south) / DEM_RES)
        band = read_band(crops, west, north, DEM_RES, ncols, nrows, np.float32, fill=0)
        band[~np.isfinite(band) | (band < -1000.0)] = 0.0
        fx = (lons - west) / DEM_RES - 0.5
        fz = (north - lats[j0:j1]) / DEM_RES - 0.5
        out[j0:j1] = bilinear_grid(band, fx, fz).astype(np.float32)
    return out


def build_landcover(proj: Projection, crops: list[Crop]) -> tuple[np.ndarray, int]:
    """Majority WorldCover class per output cell. Cell i covers the metres around sample i (half-cell each side)."""
    n = LANDCOVER_N
    cell = proj.size / (n - 1)
    zs = proj.grid(n)
    xs = proj.grid(n)
    lons = proj.lon_of_x(xs)
    out = np.empty((n, n), dtype=np.uint8)
    empty_cells = 0
    west = snap_down(proj.lon_of_x(-proj.half - cell) - BAND_PAD_DEG, WC_RES)
    east = snap_up(proj.lon_of_x(proj.half + cell) + BAND_PAD_DEG, WC_RES)
    for j0 in range(0, n, BLOCK_ROWS):
        j1 = min(n, j0 + BLOCK_ROWS)
        bh = j1 - j0
        lat_hi = proj.lat_of_z(zs[j0] - cell / 2)
        lat_lo = proj.lat_of_z(zs[j1 - 1] + cell / 2)
        north = snap_up(lat_hi + BAND_PAD_DEG, WC_RES)
        south = snap_down(lat_lo - BAND_PAD_DEG, WC_RES)
        ncols = round((east - west) / WC_RES)
        nrows = round((north - south) / WC_RES)
        codes = read_band(crops, west, north, WC_RES, ncols, nrows, np.uint8, fill=0)
        cls = WC_LUT[codes].astype(np.int64)
        col_lon = west + (np.arange(ncols) + 0.5) * WC_RES
        row_lat = north - (np.arange(nrows) + 0.5) * WC_RES
        cx = np.floor((proj.x_of_lon(col_lon) + proj.half) / cell + 0.5).astype(np.int64)
        cz = np.floor((proj.z_of_lat(row_lat) + proj.half) / cell + 0.5).astype(np.int64) - j0
        ok_c = (cx >= 0) & (cx < n)
        ok_r = (cz >= 0) & (cz < bh)
        cxc = np.clip(cx, 0, n - 1)
        czc = np.clip(cz, 0, bh - 1)
        key = (czc[:, None] * n + cxc[None, :]) * 9 + cls
        sink = bh * n * 9
        key = np.where(ok_r[:, None] & ok_c[None, :], key, sink)
        counts = np.bincount(key.ravel(), minlength=sink + 1)[:sink].reshape(bh, n, 9)
        empty_cells += int((counts.sum(axis=2) == 0).sum())
        out[j0:j1] = counts.argmax(axis=2).astype(np.uint8)
    return out, empty_cells


# ======================================================================
# Sea, runways and final height
# ======================================================================
def sea_mask(raw_height: np.ndarray, landcover: np.ndarray) -> np.ndarray:
    return (raw_height <= 0.0) & (landcover == LC_WATER)


def flatten_runways(height: np.ndarray, sea: np.ndarray, proj: Projection, zones: list[dict]) -> None:
    """Set land under each runway to its mean elevation, blended out over RUNWAY_BLEND_M."""
    n = height.shape[0]
    cell = proj.size / (n - 1)
    for zone in zones:
        x1, z1, x2, z2 = zone["x1"], zone["z1"], zone["x2"], zone["z2"]
        hw = zone["width_m"] / 2.0
        pad = hw + RUNWAY_BLEND_M + cell
        i0 = max(0, int(math.floor((min(x1, x2) - pad + proj.half) / cell)))
        i1 = min(n, int(math.ceil((max(x1, x2) + pad + proj.half) / cell)) + 1)
        j0 = max(0, int(math.floor((min(z1, z2) - pad + proj.half) / cell)))
        j1 = min(n, int(math.ceil((max(z1, z2) + pad + proj.half) / cell)) + 1)
        xs = -proj.half + np.arange(i0, i1) * cell
        zs = -proj.half + np.arange(j0, j1) * cell
        vx, vz = x2 - x1, z2 - z1
        length2 = vx * vx + vz * vz
        px = xs[None, :] - x1
        pz = zs[:, None] - z1
        t = np.clip((px * vx + pz * vz) / length2, 0.0, 1.0)
        dist = np.hypot(px - t * vx, pz - t * vz)
        tb = np.clip((dist - hw) / RUNWAY_BLEND_M, 0.0, 1.0)
        weight = 1.0 - tb * tb * (3.0 - 2.0 * tb)
        region = height[j0:j1, i0:i1]
        blended = weight * zone["elevation_m"] + (1.0 - weight) * region
        height[j0:j1, i0:i1] = np.where(sea[j0:j1, i0:i1], region, blended)


def finalize_height(proj: Projection, raw: np.ndarray, sea: np.ndarray, zones: list[dict]) -> np.ndarray:
    height = raw.astype(np.float32, copy=True)
    flatten_runways(height, sea, proj, zones)
    cell = proj.size / (HEIGHT_N - 1)
    dist = ndimage.distance_transform_edt(sea, sampling=cell)  # distance of each sea cell to nearest land
    depth = SEA_NEAR_DEPTH_M + (SEA_FAR_DEPTH_M - SEA_NEAR_DEPTH_M) * np.minimum(dist / SEA_FULL_DEPTH_DIST_M, 1.0)
    height[sea] = depth[sea].astype(np.float32)
    del dist, depth
    low_land = (~sea) & (height <= 0.0)
    height[low_land] = LAND_MIN_HEIGHT_M
    log(f"  land below/at sea level lifted: {int(low_land.sum())} cells; sea cells: {int(sea.sum())}")
    return height


# ======================================================================
# Colour (EOX Sentinel-2 cloudless, Web Mercator tiles)
# ======================================================================
def merc_x(lon):
    return (np.asarray(lon, dtype=np.float64) + 180.0) / 360.0 * (256.0 * 2 ** EOX_ZOOM)


def merc_y(lat):
    lat_r = np.radians(np.asarray(lat, dtype=np.float64))
    return (1.0 - np.arcsinh(np.tan(lat_r)) / math.pi) / 2.0 * (256.0 * 2 ** EOX_ZOOM)


def fetch_url(url: str, dst: Path) -> bool:
    if dst.exists():
        return True
    dst.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(6):
        try:
            r = requests.get(url, timeout=60, headers={"User-Agent": USER_AGENT})
            if r.status_code == 200 and r.content:
                tmp = dst.parent / (dst.name + ".part")
                tmp.write_bytes(r.content)
                os.replace(tmp, dst)
                return True
            if r.status_code == 404:
                return False
        except requests.RequestException:
            pass
        time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"failed to download {url}")


def build_colour(proj: Projection, landcover: np.ndarray) -> np.ndarray:
    n = COLOR_N
    west, south, east, north = proj.bounds()
    tx0 = int(math.floor(merc_x(west) / 256.0))
    tx1 = int(math.floor(merc_x(east) / 256.0))
    ty0 = int(math.floor(merc_y(north) / 256.0))
    ty1 = int(math.floor(merc_y(south) / 256.0))
    tiles = [(x, y) for y in range(ty0, ty1 + 1) for x in range(tx0, tx1 + 1)]
    log(f"  colour: {len(tiles)} EOX tiles at zoom {EOX_ZOOM} (cache reused)")

    def fetch(xy):
        x, y = xy
        url = EOX_URL.format(z=EOX_ZOOM, y=y, x=x)
        return fetch_url(url, CACHE / "eox" / str(EOX_ZOOM) / str(y) / f"{x}.jpg")

    with cf.ThreadPoolExecutor(max_workers=4) as pool:
        done = 0
        for ok in pool.map(fetch, tiles):
            done += 1
            if done % 500 == 0:
                log(f"  colour tiles {done}/{len(tiles)}")
            if not ok:
                log("  warning: missing EOX tile (left black)")

    zs = proj.grid(n)
    xs = proj.grid(n)
    lons = proj.lon_of_x(xs)
    lats = proj.lat_of_z(zs)
    mx = merc_x(lons) - tx0 * 256.0  # canvas-relative pixel coordinates, all columns
    my = merc_y(lats)
    out = np.empty((n, n, 3), dtype=np.uint8)
    for j0 in range(0, n, COLOR_BLOCK_ROWS):
        j1 = min(n, j0 + COLOR_BLOCK_ROWS)
        ya = int(math.floor(my[j0:j1].min() / 256.0))
        yb = int(math.floor(my[j0:j1].max() / 256.0))
        canvas = np.zeros(((yb - ya + 1) * 256, (tx1 - tx0 + 1) * 256, 3), dtype=np.uint8)
        for ty in range(ya, yb + 1):
            for tx in range(tx0, tx1 + 1):
                path = CACHE / "eox" / str(EOX_ZOOM) / str(ty) / f"{tx}.jpg"
                if not path.exists():
                    continue
                tile = np.asarray(Image.open(path).convert("RGB"))
                canvas[(ty - ya) * 256:(ty - ya + 1) * 256, (tx - tx0) * 256:(tx - tx0 + 1) * 256] = tile
        fx = mx - 0.5
        fy = my[j0:j1] - ya * 256.0 - 0.5
        c0 = np.clip(np.floor(fx).astype(np.int64), 0, canvas.shape[1] - 2)
        r0 = np.clip(np.floor(fy).astype(np.int64), 0, canvas.shape[0] - 2)
        tc = np.clip(fx - c0, 0.0, 1.0)[None, :, None].astype(np.float32)
        tr = np.clip(fy - r0, 0.0, 1.0)[:, None, None].astype(np.float32)
        v00 = canvas[r0[:, None], c0[None, :]].astype(np.float32)
        v01 = canvas[r0[:, None], c0[None, :] + 1].astype(np.float32)
        v10 = canvas[r0[:, None] + 1, c0[None, :]].astype(np.float32)
        v11 = canvas[r0[:, None] + 1, c0[None, :] + 1].astype(np.float32)
        top = v00 + (v01 - v00) * tc
        bot = v10 + (v11 - v10) * tc
        out[j0:j1] = np.clip(top + (bot - top) * tr + 0.5, 0, 255).astype(np.uint8)
    return out


def grade_colour(colour: np.ndarray, landcover: np.ndarray) -> np.ndarray:
    """Global white balance, mild contrast and saturation boost, neutral deep blue-grey sea. In place."""
    n = colour.shape[0]
    idx = np.rint(np.arange(n) * (LANDCOVER_N - 1) / (n - 1)).astype(np.int64)
    sea = landcover[np.ix_(idx, idx)] == LC_WATER
    sub = colour[::8, ::8].reshape(-1, 3).astype(np.float64)
    land = ~sea[::8, ::8].reshape(-1)
    means = sub[land].mean(axis=0)
    gains = np.clip(means.mean() / means, *GRADE_WB_CLAMP)
    log(f"  white balance gains (R,G,B): {gains.round(3).tolist()}")
    luma_w = np.array([0.299, 0.587, 0.114], dtype=np.float32)
    rows = 1024
    for r0 in range(0, n, rows):
        r1 = min(n, r0 + rows)
        f = colour[r0:r1].astype(np.float32) * gains.astype(np.float32)
        luma = (f @ luma_w)[..., None]
        f = luma + (f - luma) * GRADE_SATURATION
        f = (f - 128.0) * GRADE_CONTRAST + 128.0
        sea_blk = sea[r0:r1, :, None]
        lum01 = np.clip(luma / 255.0, 0.0, 1.0)
        sea_col = SEA_TINT[None, None, :] * (0.75 + 0.5 * lum01)
        f = np.where(sea_blk, f + (sea_col - f) * SEA_TINT_MIX, f)
        colour[r0:r1] = np.clip(f + 0.5, 0, 255).astype(np.uint8)
    return colour


# ======================================================================
# OpenStreetMap: airports, places, roads (Overpass)
# ======================================================================
def overpass(map_id: str, label: str, query: str) -> dict:
    cache_file = CACHE / "overpass" / f"{map_id}_{label}.json"
    if cache_file.exists():
        return json.loads(cache_file.read_text())
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(5):
        try:
            r = requests.post(OVERPASS_URL, data={"data": query}, timeout=600,
                              headers={"User-Agent": USER_AGENT})
            if r.status_code == 200:
                data = r.json()
                cache_file.write_text(json.dumps(data))
                log(f"  overpass {label}: {len(data.get('elements', []))} elements")
                return data
            log(f"  overpass {label}: HTTP {r.status_code}, retrying")
        except (requests.RequestException, ValueError) as exc:
            log(f"  overpass {label}: {exc}, retrying")
        time.sleep(20 * (attempt + 1))
    raise RuntimeError(f"Overpass query {label} failed")


def name_of(tags: dict) -> str:
    for key in ("name:en", "name:fr", "name"):
        if tags.get(key):
            return tags[key]
    return ""


def parse_population(text: str | None) -> int:
    if not text:
        return 0
    m = re.search(r"\d[\d ,.]*", text)
    if not m:
        return 0
    digits = re.sub(r"[ ,.]", "", m.group(0))
    return int(digits) if digits.isdigit() else 0


def parse_width(text: str | None) -> float | None:
    if not text:
        return None
    m = re.search(r"\d+(\.\d+)?", text)
    return float(m.group(0)) if m else None


def is_paved(surface: str | None) -> bool:
    s = (surface or "").strip().lower()
    if not s:
        return True  # unknown surface on a long runway is treated as paved
    if "unpaved" in s:
        return False
    return any(k in s for k in ("asphalt", "concrete", "paved", "paving", "metal"))


def polyline_length(xz: np.ndarray) -> float:
    d = np.diff(xz, axis=0)
    return float(np.hypot(d[:, 0], d[:, 1]).sum())


def geometry_xz(proj: Projection, geom: list[dict]) -> np.ndarray:
    lon = np.array([p["lon"] for p in geom], dtype=np.float64)
    lat = np.array([p["lat"] for p in geom], dtype=np.float64)
    return np.stack([proj.x_of_lon(lon), proj.z_of_lat(lat)], axis=1)


def sample_polyline(xz: np.ndarray, step: float) -> np.ndarray:
    pts = [xz[0]]
    for a, b in zip(xz[:-1], xz[1:]):
        seg = float(np.hypot(*(b - a)))
        k = max(1, int(math.ceil(seg / step)))
        for i in range(1, k + 1):
            pts.append(a + (b - a) * (i / k))
    return np.array(pts)


def nearest_aerodrome(aerodromes: list[dict], mid: np.ndarray) -> dict | None:
    best, best_d = None, AIRPORT_MATCH_RADIUS_M
    for ad in aerodromes:
        d = math.hypot(ad["x"] - mid[0], ad["z"] - mid[1])
        if d < best_d:
            best, best_d = ad, d
    return best


def merge_runway_segments(segs: list[dict]) -> np.ndarray:
    """End points of one runway. Several OSM ways (split at taxiway joins) are merged along their main axis."""
    if len(segs) == 1:
        return segs[0]["xz"]
    pts = np.concatenate([s["xz"] for s in segs])
    c = pts.mean(axis=0)
    _, _, vt = np.linalg.svd(pts - c, full_matrices=False)
    t = (pts - c) @ vt[0]
    return np.array([pts[int(np.argmin(t))], pts[int(np.argmax(t))]])


def orient_by_ref(xz: np.ndarray, ref: str) -> np.ndarray:
    """Start the runway at the threshold named by the first number of its ref ('09/27' starts at heading 090)."""
    m = re.match(r"^\s*(\d{1,2})", ref or "")
    if not m:
        return xz
    want = (int(m.group(1)) * 10) % 360
    d = xz[-1] - xz[0]
    heading = math.degrees(math.atan2(d[0], -d[1])) % 360.0
    diff = abs((heading - want + 180.0) % 360.0 - 180.0)
    return xz[::-1] if diff > 90.0 else xz


def build_airports(proj: Projection, osm: dict, raw_height: np.ndarray, sea: np.ndarray):
    aerodromes: list[dict] = []
    ways: list[dict] = []
    for el in osm.get("elements", []):
        tags = el.get("tags", {})
        if tags.get("aeroway") == "aerodrome":
            if el["type"] == "node":
                lat, lon = el["lat"], el["lon"]
            else:
                pts = el.get("geometry") or [p for m in el.get("members", []) for p in m.get("geometry", [])]
                if not pts:
                    continue
                lat = float(np.mean([p["lat"] for p in pts]))
                lon = float(np.mean([p["lon"] for p in pts]))
            aerodromes.append({"name": name_of(tags), "icao": tags.get("icao", tags.get("ref:icao", "")),
                               "x": float(proj.x_of_lon(lon)), "z": float(proj.z_of_lat(lat))})
        elif tags.get("aeroway") == "runway" and el["type"] == "way" and el.get("geometry"):
            if is_paved(tags.get("surface")):
                ways.append({"id": el["id"], "ref": tags.get("ref", ""),
                             "xz": geometry_xz(proj, el["geometry"]),
                             "width": parse_width(tags.get("width")) or RUNWAY_DEFAULT_WIDTH_M})

    # One bucket per physical runway: same airport and same ref (ways split at taxiways share both).
    buckets: dict[tuple[str, str], dict] = {}
    for w in ways:
        mid = 0.5 * (w["xz"][0] + w["xz"][-1])
        ad = nearest_aerodrome(aerodromes, mid)
        if ad is None:
            key = f"unnamed {round(mid[0] / 5000.0)},{round(mid[1] / 5000.0)}"
            name, icao = "", ""
        else:
            key = ad["icao"] or ad["name"] or f"{ad['x']:.0f},{ad['z']:.0f}"
            name, icao = ad["name"], ad["icao"]
        bucket = buckets.setdefault((key, w["ref"] or f"way{w['id']}"),
                                    {"name": name, "icao": icao, "ref": w["ref"], "segs": []})
        bucket["segs"].append(w)

    sea_f = sea.astype(np.float32)
    groups: dict[str, dict] = {}
    zones: list[dict] = []
    for (key, _), bucket in buckets.items():
        xz = orient_by_ref(merge_runway_segments(bucket["segs"]), bucket["ref"])
        length = polyline_length(xz)
        if length < RUNWAY_MIN_LENGTH_M:
            continue
        width = float(np.median([s["width"] for s in bucket["segs"]]))
        pts = sample_polyline(xz, RUNWAY_SAMPLE_STEP_M)
        elev = sample_grid_xz(raw_height, proj, pts[:, 0], pts[:, 1])
        on_sea = sample_grid_xz(sea_f, proj, pts[:, 0], pts[:, 1]) > 0.5
        land = elev[~on_sea]
        elevation = float(land.mean()) if land.size else float(elev.mean())
        x1, z1 = float(xz[0, 0]), float(xz[0, 1])
        x2, z2 = float(xz[-1, 0]), float(xz[-1, 1])
        heading = math.degrees(math.atan2(x2 - x1, -(z2 - z1))) % 360.0
        group = groups.setdefault(key, {"name": bucket["name"] or "Airfield", "icao": bucket["icao"], "runways": []})
        group["runways"].append({
            "ref": bucket["ref"], "x1": round(x1, 1), "z1": round(z1, 1), "x2": round(x2, 1), "z2": round(z2, 1),
            "heading_deg": round(heading, 2), "length_m": round(length, 1),
            "width_m": round(width, 1), "elevation_m": round(elevation, 2),
        })
        zones.append({"x1": x1, "z1": z1, "x2": x2, "z2": z2, "width_m": width, "elevation_m": elevation})

    airports = []
    for group in groups.values():
        group["runways"].sort(key=lambda r: r["ref"])
        airports.append(group)
    airports.sort(key=lambda a: a["name"])
    log(f"  airports: {len(airports)} with {len(zones)} paved runways >= {RUNWAY_MIN_LENGTH_M:.0f} m")
    return airports, zones


def build_places(proj: Projection, osm: dict) -> list[dict]:
    places = []
    for el in osm.get("elements", []):
        tags = el.get("tags", {})
        if el["type"] != "node" or tags.get("place") not in ("city", "town"):
            continue
        name = name_of(tags)
        if not name:
            continue
        x = float(proj.x_of_lon(el["lon"]))
        z = float(proj.z_of_lat(el["lat"]))
        if abs(x) > proj.half or abs(z) > proj.half:
            continue
        places.append({"name": name, "x": round(x, 1), "z": round(z, 1),
                       "population": parse_population(tags.get("population")), "kind": tags["place"]})
    places.sort(key=lambda p: -p["population"])
    log(f"  places: {len(places)}")
    return places


def douglas_peucker(pts: np.ndarray, eps: float) -> np.ndarray:
    n = len(pts)
    if n < 3:
        return pts
    keep = np.zeros(n, dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        p, q = pts[a], pts[b]
        seg = q - p
        length = math.hypot(seg[0], seg[1])
        mid = pts[a + 1:b]
        if length < 1e-9:
            dists = np.hypot(mid[:, 0] - p[0], mid[:, 1] - p[1])
        else:
            dists = np.abs(seg[0] * (mid[:, 1] - p[1]) - seg[1] * (mid[:, 0] - p[0])) / length
        k = int(np.argmax(dists))
        if dists[k] > eps:
            idx = a + 1 + k
            keep[idx] = True
            stack.append((a, idx))
            stack.append((idx, b))
    return pts[keep]


def clip_segment(p: np.ndarray, q: np.ndarray, lo: float, hi: float):
    """Liang-Barsky clip of segment pq to the square [lo, hi]^2. Returns (p', q') or None."""
    d = q - p
    t0, t1 = 0.0, 1.0
    for pp, qq in ((-d[0], p[0] - lo), (d[0], hi - p[0]), (-d[1], p[1] - lo), (d[1], hi - p[1])):
        if pp == 0.0:
            if qq < 0.0:
                return None
            continue
        r = qq / pp
        if pp < 0.0:
            if r > t1:
                return None
            t0 = max(t0, r)
        else:
            if r < t0:
                return None
            t1 = min(t1, r)
    return p + t0 * d, p + t1 * d


def build_roads(proj: Projection, osm: dict) -> list[list[list[float]]]:
    pieces: list[np.ndarray] = []
    lo, hi = -proj.half, proj.half
    for el in osm.get("elements", []):
        if el["type"] != "way" or not el.get("geometry"):
            continue
        xz = geometry_xz(proj, el["geometry"])
        xz = douglas_peucker(xz, ROAD_SIMPLIFY_M)
        current: list[np.ndarray] = []
        for a, b in zip(xz[:-1], xz[1:]):
            clipped = clip_segment(a, b, lo, hi)
            if clipped is None:
                if len(current) >= 2:
                    pieces.append(np.array(current))
                current = []
                continue
            p, q = clipped
            if current and np.hypot(*(current[-1] - p)) < 1e-6:
                current.append(q)
            else:
                if len(current) >= 2:
                    pieces.append(np.array(current))
                current = [p, q]
        if len(current) >= 2:
            pieces.append(np.array(current))
    pieces.sort(key=lambda pl: -polyline_length(pl))
    kept = pieces[:ROAD_MAX_POLYLINES]
    log(f"  roads: {len(pieces)} pieces, keeping {len(kept)} longest")
    return [[[round(float(x), 1), round(float(z), 1)] for x, z in pl] for pl in kept]


# ======================================================================
# Previews and checks
# ======================================================================
def write_previews(map_id: str, height: np.ndarray, landcover: np.ndarray, colour: np.ndarray, cell: float) -> None:
    gy, gx = np.gradient(height.astype(np.float64), cell)
    nx, ny, nz = -gx, np.ones_like(gx), -gy  # (east, up, south)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    light = np.array([-0.5, 0.7, -0.5])
    light /= np.linalg.norm(light)
    shade = np.clip((nx * light[0] + ny * light[1] + nz * light[2]) / norm, 0.0, 1.0)
    shade_img = (40 + 200 * shade).astype(np.uint8)
    shade_img[height <= 0.0] = 70
    Image.fromarray(shade_img[::4, ::4]).save(PREVIEW_DIR / f"map_preview_{map_id}_hillshade.png")
    Image.fromarray(LC_PALETTE[landcover[::4, ::4]]).save(PREVIEW_DIR / f"map_preview_{map_id}_landcover.png")
    Image.fromarray(colour[::8, ::8]).save(PREVIEW_DIR / f"map_preview_{map_id}_colour.png")
    log(f"  previews written to {PREVIEW_DIR}/map_preview_{map_id}_*.png")


def height_from_file(meta: dict, lat: float, lon: float) -> float:
    """Same formula as Ground.world_height_at (bilinear), read straight from the written files."""
    proj = Projection(meta["center_lat"], meta["center_lon"], meta["size_m"])
    n = meta["height_n"]
    raw = np.fromfile(ROOT / "game" / meta["height_file"].replace("res://", ""), dtype="<u2")
    raw = raw.reshape(n, n).astype(np.float64)
    x = float(proj.x_of_lon(lon))
    z = float(proj.z_of_lat(lat))
    n1 = n - 1
    u = min(max((x / meta["size_m"] + 0.5) * n1, 0.0), n1)
    v = min(max((z / meta["size_m"] + 0.5) * n1, 0.0), n1)
    x0 = min(int(u), n1 - 1)
    y0 = min(int(v), n1 - 1)
    fx, fy = u - x0, v - y0
    h00, h10 = raw[y0, x0], raw[y0, x0 + 1]
    h01, h11 = raw[y0 + 1, x0], raw[y0 + 1, x0 + 1]
    hv = (h00 + (h10 - h00) * fx) + ((h01 + (h11 - h01) * fx) - (h00 + (h10 - h00) * fx)) * fy
    return meta["height_min"] + hv / 65535.0 * (meta["height_max"] - meta["height_min"])


def check_map(meta: dict) -> None:
    landmarks = {"gibraltar": [("Rock of Gibraltar summit (~426 m)", 36.1447, -5.3527),
                               ("Strait, mid-channel (sea)", 35.95, -5.65)],
                 "atlas": [("Jbel Toubkal summit (4167 m)", 31.0595, -7.9144),
                           ("Marrakech city centre (~460 m)", 31.6295, -7.9811)]}
    proj = Projection(meta["center_lat"], meta["center_lon"], meta["size_m"])
    n = meta["height_n"]
    cell = meta["size_m"] / (n - 1)
    raw = np.fromfile(ROOT / "game" / meta["height_file"].replace("res://", ""), dtype="<u2").reshape(n, n)
    decoded = meta["height_min"] + raw.astype(np.float64) / 65535.0 * (meta["height_max"] - meta["height_min"])
    rad = int(500.0 / cell)
    for label, lat, lon in landmarks.get(meta["id"], []):
        c = int(round((float(proj.x_of_lon(lon)) + meta["size_m"] / 2) / cell))
        r = int(round((float(proj.z_of_lat(lat)) + meta["size_m"] / 2) / cell))
        block = decoded[max(r - rad, 0):r + rad + 1, max(c - rad, 0):c + rad + 1]
        log(f"  check {label}: point {height_from_file(meta, lat, lon):.1f} m, "
            f"max within 500 m {float(block.max()):.1f} m")


# ======================================================================
# Build one map
# ======================================================================
def build_map(mdef: dict, previews: bool) -> None:
    map_id = mdef["id"]
    t0 = time.time()
    proj = Projection(mdef["center_lat"], mdef["center_lon"], mdef["size_m"])
    west, south, east, north = proj.bounds()
    log(f"[{map_id}] {mdef['name']}: lat {south:.4f}..{north:.4f}, lon {west:.4f}..{east:.4f}")
    bounds = proj.padded_bounds(SOURCE_PAD_DEG)

    dem_crops, wc_crops = fetch_sources(map_id, bounds)
    log(f"[{map_id}] heights (Copernicus DEM, bilinear)")
    raw = build_raw_height(proj, dem_crops)
    log(f"  raw DEM: min {raw.min():.1f} max {raw.max():.1f} mean {raw.mean():.1f} m")
    log(f"[{map_id}] land cover (WorldCover, majority)")
    landcover, empty = build_landcover(proj, wc_crops)
    hist = np.bincount(landcover.ravel(), minlength=9)
    log("  classes: " + ", ".join(f"{i}:{100.0 * c / landcover.size:.1f}%" for i, c in enumerate(hist)))
    log(f"  cells without any source pixel: {empty}")

    log(f"[{map_id}] OpenStreetMap")
    pad = 0.02
    bb = f"{south - pad},{west - pad},{north + pad},{east + pad}"
    runway_osm = overpass(map_id, "airports", (
        f'[out:json][timeout:600];(way["aeroway"="runway"]({bb});'
        f'node["aeroway"="aerodrome"]({bb});way["aeroway"="aerodrome"]({bb});'
        f'relation["aeroway"="aerodrome"]({bb}););out geom;'))
    places_osm = overpass(map_id, "places", (
        f'[out:json][timeout:600];node["place"~"^(city|town)$"]({bb});out body;'))
    roads_osm = overpass(map_id, "roads", (
        f'[out:json][timeout:600];way["highway"~"^(motorway|trunk|primary)$"]({bb});out geom;'))

    sea = sea_mask(raw, landcover)
    airports, zones = build_airports(proj, runway_osm, raw, sea)
    places = build_places(proj, places_osm)
    roads = build_roads(proj, roads_osm)

    log(f"[{map_id}] final height (flatten runways, sea depth)")
    height = finalize_height(proj, raw, sea, zones)
    del raw
    hmin = float(math.floor(height.min()))
    hmax = float(math.ceil(height.max()))
    if hmax - hmin < 1.0:
        hmax = hmin + 1.0
    log(f"  height range {hmin:.0f}..{hmax:.0f} m")

    log(f"[{map_id}] colour (EOX Sentinel-2 cloudless, zoom {EOX_ZOOM})")
    colour = build_colour(proj, landcover)
    colour = grade_colour(colour, landcover)

    out_dir = ASSETS_DIR / map_id
    out_dir.mkdir(parents=True, exist_ok=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    q = np.clip(np.rint((height - hmin) * (65535.0 / (hmax - hmin))), 0, 65535).astype("<u2")
    q.tofile(out_dir / "height.r16")
    landcover.tofile(out_dir / "landcover.u8")
    Image.fromarray(colour).save(out_dir / "color.jpg", quality=JPEG_QUALITY, optimize=True)
    log(f"  wrote height.r16 ({(out_dir / 'height.r16').stat().st_size / 1e6:.1f} MB), landcover.u8 "
        f"({(out_dir / 'landcover.u8').stat().st_size / 1e6:.1f} MB), color.jpg "
        f"({(out_dir / 'color.jpg').stat().st_size / 1e6:.1f} MB)")

    spawn = mdef["spawn"]
    spawn_x = float(proj.x_of_lon(spawn["lon"]))
    spawn_z = float(proj.z_of_lat(spawn["lat"]))
    meta = {
        "id": map_id,
        "name": mdef["name"],
        "description": mdef["description"],
        "center_lat": mdef["center_lat"],
        "center_lon": mdef["center_lon"],
        "size_m": int(mdef["size_m"]),
        "sea_level": 0.0,
        "height_file": f"res://assets/maps/{map_id}/height.r16",
        "height_n": HEIGHT_N,
        "height_min": hmin,
        "height_max": hmax,
        "landcover_file": f"res://assets/maps/{map_id}/landcover.u8",
        "landcover_n": LANDCOVER_N,
        "color_file": f"res://assets/maps/{map_id}/color.jpg",
        "airports": airports,
        "places": places,
        "roads": roads,
        "spawn": {"x": round(spawn_x, 1), "z": round(spawn_z, 1), "alt_m": spawn["alt_m"],
                  "heading_deg": spawn["heading_deg"]},
        "attribution": ATTRIBUTION,
    }
    (DATA_DIR / f"{map_id}.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False) + "\n")
    log(f"  wrote {DATA_DIR / (map_id + '.json')}")

    check_map(meta)
    if previews:
        write_previews(map_id, height, landcover, colour, proj.size / (HEIGHT_N - 1))
    log(f"[{map_id}] done in {time.time() - t0:.0f}s")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--maps", nargs="*", default=None, help="map ids from tools/maps.json (default: all)")
    ap.add_argument("--no-previews", action="store_true", help="skip the /tmp preview PNGs")
    args = ap.parse_args()
    defs = json.loads((TOOLS_DIR / "maps.json").read_text())["maps"]
    if args.maps:
        defs = [d for d in defs if d["id"] in args.maps]
        if not defs:
            log("no matching map ids")
            return 1
    for mdef in defs:
        build_map(mdef, previews=not args.no_previews)
    return 0


if __name__ == "__main__":
    sys.exit(main())
