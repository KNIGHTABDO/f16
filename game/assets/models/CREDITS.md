# Model credits

Models below are converted from FlightGear aircraft sources (AC3D + FG XML) to GLB by
`tools/convert_models.py`. Recipes are in `tools/models.json`. Source checkouts are
fetched by `tools/fetch_models.sh` into `tools/cache/models/` (not committed).

## Converted

| Id | Aircraft | Source repo | Licence | Files |
|----|----------|-------------|---------|-------|
| f16c | Lockheed Martin F-16C | https://github.com/NikolaiVChr/f16 | GPL-2.0 (LICENSE file in repo) | `aircraft/f16c/f16c.glb` |
| ef2000 | Eurofighter EF-2000 Typhoon | https://github.com/IAHM-COL/EF-Typhoon | GPL-2.0 (LICENSE file in repo) | `aircraft/ef2000/ef2000.glb` |
| f35a | Lockheed Martin F-35A | https://github.com/PaoloAmoroso/F-35A | GPL-2.0 (LICENSE file in repo) | `aircraft/f35a/f35a.glb` |
| su27 | Sukhoi Su-27SK (Flanker) | https://github.com/yanes19/SU-27SK | GPL-2.0 (LICENSE header) | `aircraft/su27/su27.glb` |
| mig29 | Mikoyan MiG-29 (FlightGear FGAddon) | https://svn.code.sf.net/p/flightgear/fgaddon/trunk/Aircraft/Mig-29 | GPL-2.0 (COPYING.txt) | `aircraft/mig29/mig29.glb` |
| f15c | McDonnell Douglas F-15C Eagle (model by Enrique Laso, port by Richard Harrison) | https://github.com/Zaretto/F-15 | UNVERIFIED: no LICENSE file or licence text in repo; confirm before distribution | `aircraft/f15c/f15c.glb` |

The GLB files embed the original FlightGear textures. The original authors are listed in each
repository's history and README. Models are redistributed under the GPL with the licence
text from each repository.

## Sourced but not converted yet (licence status noted)

| Id | Source repo | Licence status |
|----|-------------|----------------|
| mig21bis | https://github.com/l0k1/MiG-21bis | No LICENSE file found in repo root; needs checking |
| ja37 | https://github.com/NikolaiVChr/flightgear-saab-ja-37-viggen | GPL-2.0 (LICENSE header) |
| f14b | https://github.com/Zaretto/f-14b | No LICENSE file found; needs checking |
| mirage2000 | https://github.com/5H1N0B11/flightgear-mirage2000 | GPL-2.0 (LICENSE header) |
| a10 | https://github.com/l0k1/A-10 | No LICENSE file found; needs checking |
| p51d | https://github.com/Zaretto/p51d | No LICENSE file found; needs checking |
| f22a | https://github.com/MonotoneDevelopment/F-22 | GPL-2.0 (LICENSE header) |
| f22a (alt) | https://github.com/SamJD261/F-22-Raptor | No LICENSE file found; needs checking |
| su57 | https://github.com/ShFsn/Su-57 | GPL-3.0 (LICENSE header) |
