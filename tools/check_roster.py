#!/usr/bin/env python3
"""Validation tool for aircraft roster, specifications, and weapon loadouts."""

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "game" / "data"
AIRCRAFT_DIR = DATA_DIR / "aircraft"
WEAPONS_FILE = DATA_DIR / "weapons.json"
ROSTER_FILE = DATA_DIR / "roster.json"
F16C_FILE = AIRCRAFT_DIR / "f16c.json"

REQUIRED_WEAPON_FIELDS = {
    "gun": {"type", "name", "rpm", "muzzle_velocity", "damage", "spread_mrad", "tracer_every", "range", "sound"},
    "ir_missile": {"type", "name", "mass", "speed_max", "boost_s", "accel", "max_g", "nav_gain", "seeker_fov_deg", "lock_fov_deg", "range", "min_range", "lifetime", "proximity", "damage", "flare_resist", "targets"},
    "radar_missile": {"type", "name", "mass", "speed_max", "boost_s", "accel", "max_g", "nav_gain", "seeker_fov_deg", "lock_fov_deg", "range", "min_range", "lifetime", "proximity", "damage", "chaff_resist", "targets"},
    "ag_missile": {"type", "name", "mass", "speed_max", "boost_s", "accel", "max_g", "nav_gain", "seeker_fov_deg", "lock_fov_deg", "range", "min_range", "lifetime", "proximity", "damage", "blast_radius", "targets"},
    "rocket": {"type", "name", "mass", "speed_max", "accel", "boost_s", "spread_mrad", "damage", "blast_radius", "lifetime", "salvo", "targets"},
    "bomb": {"type", "name", "mass", "drag", "damage", "blast_radius", "targets"},
    "guided_bomb": {"type", "name", "mass", "drag", "max_g", "nav_gain", "lock_fov_deg", "damage", "blast_radius", "targets"},
}

VALID_CATEGORIES = {"fighter", "multirole", "attack", "interceptor", "prop", "bomber", "helicopter"}


def match_type(val, ref_val):
    if isinstance(ref_val, (int, float)) and isinstance(val, (int, float)):
        return True
    return type(val) is type(ref_val)


def main() -> int:
    errors = []

    if not F16C_FILE.exists():
        print(f"ERROR: {F16C_FILE} missing")
        return 1

    with open(F16C_FILE, "r", encoding="utf-8") as f:
        f16_schema = json.load(f)

    if not WEAPONS_FILE.exists():
        print(f"ERROR: {WEAPONS_FILE} missing")
        return 1

    with open(WEAPONS_FILE, "r", encoding="utf-8") as f:
        weapons_data = json.load(f)

    # Validate weapons.json
    for weapon_id, wdata in weapons_data.items():
        wtype = wdata.get("type")
        if not wtype:
            errors.append(f"weapons.json: weapon '{weapon_id}' has no 'type'")
            continue
        req_keys = REQUIRED_WEAPON_FIELDS.get(wtype)
        if not req_keys:
            errors.append(f"weapons.json: weapon '{weapon_id}' has unknown type '{wtype}'")
            continue
        missing = req_keys - set(wdata.keys())
        if missing:
            errors.append(f"weapons.json: weapon '{weapon_id}' missing keys: {missing}")

    # Validate aircraft files
    aircraft_files = list(AIRCRAFT_DIR.glob("*.json"))
    if not aircraft_files:
        errors.append("No aircraft files found")

    aircraft_ids = set()
    for ac_path in sorted(aircraft_files):
        with open(ac_path, "r", encoding="utf-8") as f:
            ac_data = json.load(f)

        ac_id = ac_data.get("id")
        if not ac_id:
            errors.append(f"{ac_path.name}: missing 'id'")
            continue
        aircraft_ids.add(ac_id)

        # Check all keys from f16c
        for k, v in f16_schema.items():
            if k not in ac_data:
                errors.append(f"{ac_path.name}: missing key '{k}'")
            elif not match_type(ac_data[k], v):
                errors.append(
                    f"{ac_path.name}: key '{k}' type mismatch (expected {type(v).__name__}, got {type(ac_data[k]).__name__})"
                )

        # Check for extra keys
        extra = set(ac_data.keys()) - set(f16_schema.keys())
        if extra:
            errors.append(f"{ac_path.name}: unexpected extra keys: {extra}")

        # Check model path
        model = ac_data.get("model", "")
        if model != "":
            if not model.startswith("res://"):
                errors.append(f"{ac_path.name}: model '{model}' does not start with 'res://'")
            else:
                rel = model[len("res://") :]
                disk_path = ROOT / "game" / rel
                if not disk_path.exists():
                    errors.append(f"{ac_path.name}: model path '{disk_path}' does not exist on disk")

        # Check gun
        gun = ac_data.get("gun", {})
        gun_weapon = gun.get("weapon", "")
        if gun_weapon and gun_weapon not in weapons_data:
            errors.append(f"{ac_path.name}: gun weapon '{gun_weapon}' not in weapons.json")

        # Check loadouts
        loadouts = ac_data.get("loadouts", {})
        def_loadout = ac_data.get("default_loadout", "")
        if def_loadout and def_loadout not in loadouts:
            errors.append(f"{ac_path.name}: default_loadout '{def_loadout}' not in loadouts")

        for lname, litems in loadouts.items():
            for item in litems:
                w = item.get("weapon")
                cnt = item.get("count", 0)
                if w not in weapons_data:
                    errors.append(f"{ac_path.name}: loadout '{lname}' weapon '{w}' not in weapons.json")
                if cnt <= 0:
                    errors.append(f"{ac_path.name}: loadout '{lname}' weapon '{w}' count must be > 0")

    # Validate roster.json
    if not ROSTER_FILE.exists():
        errors.append(f"{ROSTER_FILE} missing")
    else:
        with open(ROSTER_FILE, "r", encoding="utf-8") as f:
            roster_data = json.load(f)

        if not isinstance(roster_data, list):
            errors.append("roster.json must be a list of aircraft entries")
        else:
            seen_roster_ids = set()
            for entry in roster_data:
                rid = entry.get("id")
                if not rid:
                    errors.append("roster.json entry missing 'id'")
                    continue
                seen_roster_ids.add(rid)

                if rid not in aircraft_ids:
                    errors.append(f"roster.json entry '{rid}' has no corresponding aircraft json file")

                cat = entry.get("category")
                if cat not in VALID_CATEGORIES:
                    errors.append(f"roster.json entry '{rid}' invalid category '{cat}'")

                cost = entry.get("unlock_cost")
                if cost is None or not isinstance(cost, (int, float)):
                    errors.append(f"roster.json entry '{rid}' invalid unlock_cost '{cost}'")
                if rid in {"f16c", "mig21bis", "p51d"} and cost != 0:
                    errors.append(f"roster.json entry '{rid}' must have unlock_cost 0 (free)")

                desc = entry.get("description", "")
                if not desc or len(desc.split(".")) < 2:
                    errors.append(f"roster.json entry '{rid}' description must be at least 2 sentences")

                stats = entry.get("stats", {})
                for stat_key in ["speed_kmh", "climb_ms", "turn_s", "ceiling_m", "guns"]:
                    if stat_key not in stats:
                        errors.append(f"roster.json entry '{rid}' stats missing '{stat_key}'")

            # Check order: by category then era
            cat_order = ["fighter", "multirole", "attack", "interceptor", "prop", "bomber", "helicopter"]
            era_order = ["ww2", "cold_war", "modern", "fifth_gen"]
            cat_rank = {c: i for i, c in enumerate(cat_order)}
            era_rank = {e: i for i, e in enumerate(era_order)}

            prev_rank = (-1, -1)
            for entry in roster_data:
                c = entry.get("category", "")
                e = entry.get("era", "")
                r = (cat_rank.get(c, 999), era_rank.get(e, 999))
                if r < prev_rank:
                    errors.append(f"roster.json out of order at '{entry.get('id')}': category '{c}' era '{e}'")
                prev_rank = r

    if errors:
        print(f"FAILED with {len(errors)} error(s):")
        for err in errors:
            print(f"  - {err}")
        return 1

    print(f"SUCCESS: {len(aircraft_files)} aircraft validated, weapons and roster OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
