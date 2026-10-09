# Map pipeline (`tools/build_map.py`)

Builds the real-world map files the game loads: height, land cover, colour and the
metadata (airports, places, roads, spawn) for every map in `tools/maps.json`.

## Run

```sh
~/.local/bin/uv run --with numpy --with rasterio --with pillow --with requests --with scipy \
    python tools/build_map.py                 # all maps
~/.local/bin/uv run --with numpy --with rasterio --with pillow --with requests --with scipy \
    python tools/build_map.py --maps gibraltar atlas --no-previews
```

- `--maps ID ...` builds only the listed ids from `maps.json`.
- `--no-previews` skips the `/tmp/map_preview_<id>_{hillshade,landcover,colour}.png` images.
- Reruns reuse `tools/cache/` and only fetch what is missing. A full first build downloads
  roughly 0.3 to 0.5 GB per map (DEM and WorldCover windows, and about 4000 EOX tiles) and
  takes tens of minutes on a slow link. Run it in the background.
- Requires GDAL/rasterio 1.4+ (wheels bundle GDAL), numpy, scipy, pillow, requests. No pip
  install is needed when using `uv run --with ...`.

## Outputs (per map id)

| File | Format | Notes |
| --- | --- | --- |
| `game/assets/maps/<id>/height.r16` | uint16 little-endian, 4096 x 4096 | `height_m = height_min + v/65535 * (height_max - height_min)` (see `game/autoload/ground.gd`) |
| `game/assets/maps/<id>/landcover.u8` | uint8, 4096 x 4096 | Ground.LC_* classes: 0 water, 1 trees, 2 shrub, 3 grass, 4 crop, 5 urban, 6 bare, 7 snow, 8 wetland |
| `game/assets/maps/<id>/color.jpg` | JPEG, 8192 x 8192, quality 90 | graded satellite colour, sea darkened to blue-grey |
| `game/data/maps/<id>.json` | JSON | id, name, size, height range, airports, places, roads, spawn, attribution |

Metadata `height_min` and `height_max` are rounded outwards to whole metres, so the uint16
quantisation step is about 0.06 m for the 2.5 km / 60 m range of these maps.

## Orientation and projection

- Local flat projection around the map centre (lat0, lon0):
  `x_east = (lon - lon0) * 111320 * cos(lat0)`, `z = -(lat - lat0) * 110574`.
  +X is east and -Z is north, as in Godot. The map spans `[-size/2, size/2]` on both axes.
- Row 0 of every raster is the north edge (z = -size/2). Column 0 is the west edge.
- Samples are corner-aligned like `ground.gd`: sample `i` sits at `-size/2 + i * size/(n-1)`.
  Each output cell is therefore sampled at its grid node, not at its pixel centre.

## Sources

| Layer | Source | Access |
| --- | --- | --- |
| Height | Copernicus DEM GLO-30 (1 arc-second, 1x1 degree COG tiles) | `copernicus-dem-30m.s3.amazonaws.com`, public. Missing tile = open sea (height 0). |
| Land cover | ESA WorldCover 2021 v200 (10 m, 3x3 degree COG tiles) | `esa-worldcover.s3.eu-central-1.amazonaws.com`, public. Majority per output cell. |
| Colour | EOX Sentinel-2 cloudless 2023, WMTS GoogleMapsCompatible, zoom 13 | `tiles.maps.eox.at`, max 4 parallel requests with retry. |
| Airports, places, roads | OpenStreetMap via Overpass | `overpass-api.de/api/interpreter`, cached as JSON in `tools/cache/overpass/`. |

Attribution (also written into each metadata file):
Copernicus DEM (c) DLR/ESA; ESA WorldCover; Sentinel-2 cloudless by EOX; (c) OpenStreetMap contributors.

## Processing

- **Height**: bilinear sampling of the DEM window per block of output rows. Sea cells are
  DEM <= 0 and WorldCover water. Their depth runs from -2 m at the coast to -60 m at 3 km
  offshore, using a distance transform. Land at or below 0 m is lifted to 0.5 m.
- **Runways**: each paved runway of at least 1500 m (ways split at taxiways are merged) is
  flattened to its mean land elevation. The flatten blends out smoothly over 300 m.
- **Land cover**: WorldCover classes are mapped to the game's Ground.LC_* values
  (`WORLDCOVER_TO_LC`). Each output cell takes the majority class of the source pixels it covers.
- **Colour**: Web Mercator tiles are bilinear-resampled to the local grid. Then a gray-world
  white balance (gains clamped to 0.85..1.15), a mild saturation (1.12) and contrast (1.08)
  boost, and the sea is tinted to a neutral deep blue-grey.
- **Roads**: `highway=motorway|trunk|primary`, Douglas-Peucker simplified (50 m), clipped to
  the map, keeping the 400 longest pieces.

## Cache layout (`tools/cache/`, gitignored)

- `dem/<id>/*.tif`, `worldcover/<id>/*.tif`: cropped windows of the remote COGs (only the map
  area is downloaded). `*.missing` markers record tiles that do not exist (sea).
- `eox/<zoom>/<y>/<x>.jpg`: colour tiles, shared between maps.
- `overpass/<id>_<query>.json`: raw Overpass responses.

Delete a subdirectory to force a refetch.

## Checks

The script prints per-layer statistics, the land-cover class shares, and the height at
landmarks read back from the written `height.r16` with the `ground.gd` formula. Gibraltar:
Rock summit (~426 m). Atlas: Jbel Toubkal (4167 m). Preview PNGs in `/tmp` show whether the
coastline lines up across height, land cover and colour.

## Dependencies on other files

- `tools/maps.json`: map definitions (centre, size, description, default spawn).
- `game/autoload/ground.gd`: binary formats, LC_* constants and the orientation convention.
