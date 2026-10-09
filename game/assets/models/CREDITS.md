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
| mig21bis | Mikoyan MiG-21bis (FlightGear; authors listed in the repo readme) | https://github.com/l0k1/MiG-21bis | GPL-3.0 (License.txt in repo) | `aircraft/mig21bis/mig21bis.glb` |
| a10c | Fairchild Republic A-10 Thunderbolt II (FlightGear) | https://github.com/l0k1/A-10 | GPL-2.0 (COPYING in repo) | `aircraft/a10c/a10c.glb` |
| b17 | Boeing B-17 Flying Fortress (FlightGear FGMEMBERS) | https://github.com/FGMEMBERS/FlyingFortress-Jsb | GPL-2.0 (COPYING in repo) | `aircraft/b17/b17.glb` |
| ja37 | Saab JA-37 Viggen (FlightGear) | https://github.com/NikolaiVChr/flightgear-saab-ja-37-viggen | GPL-2.0 (LICENSE header; no LICENSE file in our checkout, confirm) | `aircraft/ja37/ja37.glb` |
| f14b | Grumman F-14B Tomcat (FlightGear) | https://github.com/Zaretto/f-14b | UNVERIFIED: no LICENSE file found; confirm before distribution | `aircraft/f14b/f14b.glb` |
| mirage2000 | Dassault Mirage 2000-5 (FlightGear) | https://github.com/5H1N0B11/flightgear-mirage2000 | GPL-2.0 (LICENSE in repo) | `aircraft/mirage2000/mirage2000.glb` |
| p51d | North American P-51D Mustang (FlightGear) | https://github.com/Zaretto/p51d | UNVERIFIED: no LICENSE file found; confirm before distribution | `aircraft/p51d/p51d.glb` |
| f22a | Lockheed Martin F-22A Raptor (FlightGear) | https://github.com/MonotoneDevelopment/F-22 | GPL-2.0 (LICENSE in repo) | `aircraft/f22a/f22a.glb` |
| su57 | Sukhoi Su-57 (FlightGear) | https://github.com/ShFsn/Su-57 | GPL-3.0 (LICENSE header; no LICENSE file in our checkout, confirm) | `aircraft/su57/su57.glb` |
| spitfire | Supermarine Spitfire IX (FlightGear) | https://github.com/FGMEMBERS/spitfireIX | GPL-2.0 (per recipe; no LICENSE file in our checkout, confirm) | `aircraft/spitfire/spitfire.glb` |
| bf109 | Messerschmitt Bf 109G (FlightGear) | https://github.com/FGMEMBERS/bf109 | GPL-2.0 (per recipe; no LICENSE file in our checkout, confirm) | `aircraft/bf109/bf109.glb` |

The GLB files embed the original FlightGear textures. The original authors are listed in each
repository's history and README. Models are redistributed under the GPL with the licence
text from each repository.
