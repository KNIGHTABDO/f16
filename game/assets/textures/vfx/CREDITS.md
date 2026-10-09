# VFX textures: credits

All textures in this folder are procedural. `make_textures.py` generates them with Pillow and NumPy, so no third-party images, fonts or sounds are used. The generated PNGs are owned by the project under the repository licence.

| File | Size | Content |
|---|---|---|
| `smoke_flipbook.png` | 512x512, 4x4 frames | Smoke puffs for explosions and wreck columns |
| `fire_flipbook.png` | 512x512, 4x4 frames | Fire and fireball frames |
| `puff.png` | 256x256 | Soft round dust and vapour puff |
| `spark.png` | 64x64 | Hot spark dot |
| `glow.png` | 128x128 | Radial glow for lights and flares |
| `muzzle_star.png` | 256x256 | Muzzle flash star |
| `noise.png` | 256x256, greyscale | Tiling noise for shader distortion |

Regenerate from the repository root:

    uv run --with pillow,numpy python -I game/assets/textures/vfx/make_textures.py game/assets/textures/vfx
