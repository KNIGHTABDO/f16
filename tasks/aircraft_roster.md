# Task: aircraft roster data (flight specs + loadouts for every aircraft)

## Read first
`docs/ARCHITECTURE.md`, `game/data/aircraft/f16c.json` (THE schema: every file must have exactly the same keys, same units),
`game/data/weapons.json`, `game/core/flight/aircraft_data.gd` and `game/core/flight/flight_model.gd` (how each key is used),
`game/data/model_info.json` and `game/assets/models/aircraft/` (which models exist, their cockpit_eye/muzzles/nozzles/size).

## Files you own
`game/data/aircraft/<id>.json` (new files; do NOT edit f16c.json: another agent owns it; list suggested f16c changes in your report), `game/data/weapons.json`
(ADD weapons; never change existing ids or keys), `game/data/roster.json`, `tools/check_roster.py`.

## Roster (id: name, category, era) — ids must match the model folder ids in game/assets/models/aircraft/ where a model exists
Jets: f16c (F-16C Block 50), f15c, f15e, f14b, fa18c (if no model: still write data, `model` = ""), mig21bis, mig29, su27, su57, f22a,
f35a, ef2000, mirage2000, rafale (if model), ja37, a10c. Props: p51d, spitfire, bf109. Bomber: b17. Helicopter: ah64 (or the heli
model that exists; flight model uses the same keys, low speeds, high yaw rate; set "type":"helicopter").
Use real public numbers (Wikipedia-level): empty/max mass, wing area, engine thrust dry/AB (props: power -> thrust curve via keys
the FlightModel supports; read it), max speed, service ceiling, G limits, roll rates, real gun (add guns to weapons.json:
gsh23 (MiG-21), m39 (F-5), mauser_bk27, gsh301, defa554, m61a1, hispano_mk2+browning303 (spitfire), mg151, m3_browning, m230 (AH-64)),
real missiles per nation (add: r73, r27er, r77, r60, magic2, mica_ir, mica_em, meteor, iris_t, aim7m, aim54c, rb74, kh29, kh25, hellfire,
aim9b for old jets, unguided rockets s8 / s5, bombs fab250, fab500). Each new weapon uses the same keys as similar existing entries.
Loadouts: 3-4 per aircraft (air superiority, strike, CAS/rockets, mixed) that fit the hardpoints realistically.

`roster.json`: list of entries {id, name, nation, category ("fighter","multirole","attack","interceptor","prop","bomber","helicopter"),
era, unlock_cost (credits; f16c, mig21bis, p51d free; f22a/su57 most expensive), description (2 sentences), stats for the hangar
(speed_kmh, climb_ms, turn_s, ceiling_m, guns)}. Order for the hangar: by category then era.

## Validate
`tools/check_roster.py` (run with `uv run python tools/check_roster.py`): every aircraft json has every key of f16c.json with the
same type, every weapon id in loadouts exists in weapons.json, every weapon has every key its type needs, model paths exist or are "".
Then run `game/scenes/test_flight.tscn` (if present) headless for each aircraft by passing `-- --aircraft=<id>` if test_flight supports
it (read the script); otherwise write a tiny headless script under /tmp that instantiates `Aircraft.create(id, …)` per aircraft,
flies 30 s level at 70% throttle and 20 s full AB climb, and prints top speed, climb and sustained turn; compare to real values and
tune cl/cd/thrust until within ~10%. Report the table.
