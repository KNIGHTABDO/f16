#!/usr/bin/env python3
"""
generate_mode_cards.py - Creates 768x432 cinematic mode selection cards for Knight Wings.
"""

import os
from PIL import Image, ImageEnhance, ImageOps

BASE_BRAIN = "/home/knight/.gemini/antigravity-cli/brain/ae79f609-6e84-4627-b151-1aec04735672"

SOURCES = {
    "f16_gibraltar": os.path.join(BASE_BRAIN, "f16_strait_of_gibraltar_sunset_1791538436725.jpg"),
    "echelon": os.path.join(BASE_BRAIN, "fighter_jets_echelon_sunset_1791538796577.jpg"),
    "sound_barrier": os.path.join(BASE_BRAIN, "stealth_fighter_sound_barrier_1791538835126.jpg"),
    "desert_canyon": os.path.join(BASE_BRAIN, "fighter_jet_desert_canyon_1791538802325.jpg"),
    "taxiway_night": os.path.join(BASE_BRAIN, "fighter_jets_taxiway_night_1791538580710.jpg"),
    "gibraltar_sunset": os.path.join(BASE_BRAIN, "strait_of_gibraltar_sunset_1791538723936.jpg"),
    "high_atlas": os.path.join(BASE_BRAIN, "high_atlas_mountains_1791538722641.jpg"),
    "airbase_recon": os.path.join(BASE_BRAIN, "coastal_military_airbase_recon_1791538810492.jpg"),
    "sahara_dunes": os.path.join(BASE_BRAIN, "sahara_desert_dunes_sunset_1791538724147.jpg"),
}

MODES = [
    # mode_name, source_key, crop_box_frac (left, top, right, bottom), contrast, brightness
    ("free_flight", "echelon", (0.05, 0.0, 0.95, 0.9), 1.05, 1.0),
    ("instant_action", "f16_gibraltar", (0.05, 0.1, 0.95, 1.0), 1.15, 1.02),
    ("dogfight", "f16_gibraltar", (0.1, 0.05, 0.8, 0.85), 1.2, 1.05),
    ("strike", "desert_canyon", (0.0, 0.1, 1.0, 1.0), 1.15, 0.98),
    ("sead", "sound_barrier", (0.1, 0.1, 0.9, 0.9), 1.1, 1.0),
    ("anti_ship", "sound_barrier", (0.0, 0.2, 1.0, 1.0), 1.15, 0.95),
    ("convoy_hunt", "desert_canyon", (0.1, 0.2, 0.9, 1.0), 1.2, 1.0),
    ("base_defense", "taxiway_night", (0.0, 0.05, 0.9, 0.95), 1.2, 1.05),
    ("carrier_landing", "gibraltar_sunset", (0.0, 0.15, 1.0, 0.95), 1.1, 1.0),
    ("time_trial", "high_atlas", (0.05, 0.1, 0.95, 0.95), 1.15, 1.02),
    ("target_range", "airbase_recon", (0.1, 0.1, 0.9, 0.9), 1.15, 1.0),
]

def generate_mode_cards(out_dir="game/assets/ui/modes"):
    os.makedirs(out_dir, exist_ok=True)
    target_w, target_h = 768, 432
    
    for mode_name, src_key, crop_frac, contrast, brightness in MODES:
        src_path = SOURCES[src_key]
        with Image.open(src_path) as img:
            w, h = img.size
            l = int(crop_frac[0] * w)
            t = int(crop_frac[1] * h)
            r = int(crop_frac[2] * w)
            b = int(crop_frac[3] * h)
            cropped = img.crop((l, t, r, b))
            
            # Fit and resize to 768x432
            resized = ImageOps.fit(cropped, (target_w, target_h), method=Image.Resampling.LANCZOS)
            
            # Adjust contrast & brightness for punchy UI card look
            if contrast != 1.0:
                resized = ImageEnhance.Contrast(resized).enhance(contrast)
            if brightness != 1.0:
                resized = ImageEnhance.Brightness(resized).enhance(brightness)
                
            out_path = os.path.join(out_dir, f"{mode_name}.jpg")
            resized.save(out_path, "JPEG", quality=85, optimize=True, progressive=True)
            print(f"Created mode card: {out_path} ({target_w}x{target_h})")

if __name__ == "__main__":
    generate_mode_cards()
