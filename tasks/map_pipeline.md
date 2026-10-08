# Task: real-world map pipeline (Python) -> game map files

Build `tools/build_map.py`, which downloads real geodata and writes the game's map files, then run it for the maps below.
This is personal-use software; use the best free data available.

## Read first
`docs/ARCHITECTURE.md`, `game/autoload/ground.gd` (defines the binary formats and orientation, follow it exactly).

## Files you own
- `tools/build_map.py`, `tools/maps.json` (map definitions), `tools/README.md` (how to run)
- outputs: `game/assets/maps/<id>/height.r16`, `landcover.u8`, `color.jpg`, `game/data/maps/<id>.json`
- cache downloads in `tools/cache/` (gitignored). Do not commit cache files.
Python: no pip on this machine; use `uv` (`~/.local/bin/uv run --with numpy --with rasterio --with pillow --with requests ...`).
Machine: 4 cores, 7 GB RAM: process tile by tile, use float32, avoid holding several 16k x 16k float arrays at once.

## Maps (put in tools/maps.json)
1. `gibraltar`: "Strait of Gibraltar": centre 35.80 N, -5.55 E, 256 km x 256 km. (Tangier, Tetouan, Chefchaouen, Rif mountains,
   Ceuta, Gibraltar, Cadiz, Jerez, Rota, Malaga, Atlantic + Mediterranean.)
2. `atlas`: "High Atlas": centre 31.25 N, -7.55 E, 256 km x 256 km. (Marrakech, Jbel Toubkal 4167 m, Ouarzazate, desert edge.)

## Projection
Local flat projection around the centre (lat0, lon0): `x_east = (lon-lon0)*111320*cos(lat0)`, `z = -(lat-lat0)*110574`
(metres; +X east, -Z north, so north is negative Z, same as Godot). Map spans [-size/2, size/2] on both axes.
Row 0 of every raster = north edge (z = -size/2); column 0 = west edge. Sample every output pixel centre through this projection
(inverse: lon/lat from x/z) so all layers align exactly.

## Layers
1. **Height** (`height_n` = 4096): Copernicus DEM GLO-30 COG tiles, public HTTPS, no login:
   `https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N35_00_W006_00_DEM/Copernicus_DSM_COG_10_N35_00_W006_00_DEM.tif`
   (1x1 degree tiles named by SW corner; missing tiles = open sea -> height 0). Bilinear-sample to the grid.
   Sea: pixels with DEM <= 0 that are water in landcover -> set to a bathymetry-like depth: -2 m at the coast falling to -60 m
   ~3 km offshore (distance transform), so the ocean shader can show shallow water. Write uint16 with
   `height_min`/`height_max` in metadata (formula in ground.gd). Flatten terrain under every runway (see airports) to the
   runway's mean elevation with a smooth 300 m blend.
2. **Land cover** (`landcover_n` = 4096): ESA WorldCover 2021 v200 10 m tiles (3x3 degree, public HTTPS):
   `https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N33W006_Map.tif`
   (tile names = SW corner in multiples of 3 degrees). Downsample by **majority** per output pixel (read with rasterio windows /
   overview levels). Map classes to ground.gd LC_*: 10 tree->1, 20 shrub->2, 30 grass->3, 40 crop->4, 50 built->5, 60 bare->6,
   70 snow->7, 80 water->0, 90 wetland->8, 95 mangrove->8, 100 moss->3, nodata/ocean->0.
3. **Colour** (`color.jpg`, 8192 x 8192, quality 90): EOX Sentinel-2 cloudless 2023 WMTS (Web Mercator, zoom 12 or 13 then
   resample): `https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2023_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg`.
   Be polite: max 4 parallel requests, retry with backoff, cache tiles on disk. Reproject to the local grid (bilinear).
   Mild colour grading for a game look: slight contrast/saturation boost, consistent white balance, darken the sea to a
   neutral deep blue-grey (the ocean shader draws water on top).
4. **Airports** from OpenStreetMap Overpass API (`https://overpass-api.de/api/interpreter`): `aeroway=runway` ways (with `ref`,
   `width`, `surface`) and the airport name (`aeroway=aerodrome`). For each runway output: name, ref, both end points in map
   metres, heading_deg (0 = north, clockwise), length_m, width_m (default 45), elevation_m. Keep paved runways >= 1500 m.
5. **Places**: `place=city|town` nodes with name (prefer `name:en`, then `name:fr`, then `name`), population, map coords.
6. **Roads**: `highway=motorway|trunk|primary` simplified polylines (Douglas-Peucker, 50 m), as arrays of [x, z] in map metres,
   max ~400 polylines per map (keep the longest). Used for convoy routes.

## Metadata JSON (`game/data/maps/<id>.json`)
```
{ "id", "name", "description", "center_lat", "center_lon", "size_m": 256000, "sea_level": 0.0,
  "height_file": "res://assets/maps/<id>/height.r16", "height_n": 4096, "height_min", "height_max",
  "landcover_file": "res://assets/maps/<id>/landcover.u8", "landcover_n": 4096,
  "color_file": "res://assets/maps/<id>/color.jpg",
  "airports": [{"name", "icao", "runways": [{"ref","x1","z1","x2","z2","heading_deg","length_m","width_m","elevation_m"}]}],
  "places": [{"name","x","z","population","kind"}], "roads": [[[x,z],...], ...],
  "spawn": {"x","z","alt_m","heading_deg"},   // a nice default in-air spawn over the most interesting area
  "attribution": "Copernicus DEM (c) DLR/ESA; ESA WorldCover; Sentinel-2 cloudless by EOX; (c) OpenStreetMap contributors" }
```

## Verify
- Print stats per layer; save small preview PNGs to `/tmp/map_preview_<id>_*.png` (hillshade, landcover palette, colour) and look
  at them to check alignment (coastline in height, landcover and colour must line up; Gibraltar rock and Ceuta clearly visible).
- `godot --headless --path game --check-only` is not needed; but run a 10-line GDScript (scratch, not committed) or a Python check
  that reads `height.r16` with the ground.gd formula and prints the height at Gibraltar rock (~400 m) and Toubkal (~4100 m).
- File sizes: height 32 MB, landcover 16 MB, color <= 40 MB each. Commit the outputs (they are under GitHub's 100 MB limit).
