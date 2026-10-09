# World textures: credits

All textures in this folder are procedural. `make_world_textures.py` generates them with Pillow and NumPy, so no third-party images or proprietary assets are used. The generated PNGs are owned by the project under the repository licence.

| File | Size | Content |
|---|---|---|
| `tree_atlas.png` | 1024x256, RGBA | Four species side by side: pine, olive, palm, shrub |
| `runway_digits.png` | 1280x256, RGBA | Runway designator digits 0..9 side by side |
| `cloud_noise.png` | 256x256, greyscale | Seamless tileable value noise for cumulus cloud distortion |
| `asphalt.png` | 256x256, greyscale | Seamless tileable surface texture for runways and taxiways |

Regenerate from this directory:

    python3 make_world_textures.py
